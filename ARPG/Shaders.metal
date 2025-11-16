//
//  Shaders.metal
//  ARPG
//
//  Created by Digkill on 15.11.2025.
//

// File for Metal kernel and shader functions

#include <metal_stdlib>
#include <simd/simd.h>

// Including header shared between this Metal shader code and Swift/C code executing Metal API commands
#import "ShaderTypes.h"

using namespace metal;

// kGroundBaseUVScale not used in current implementation
// constant float kGroundBaseUVScale = 0.05;
constant float kIslandRadius = 200.0; // Большой радиус, чтобы покрыть всю квадратную карту
constant float kIslandEdgeWidth = 25.0;

inline float randomNoise(float2 uv, float seed)
{
    return fract(sin(dot(uv, float2(12.9898 + seed, 78.233 + seed))) * 43758.5453);
}

inline float islandMask(float2 worldXZ)
{
    float distanceFromCenter = length(worldXZ);
    float radial = 1.0 - smoothstep(kIslandRadius - kIslandEdgeWidth,
                                    kIslandRadius + kIslandEdgeWidth,
                                    distanceFromCenter);
    
    float noiseA = randomNoise(worldXZ * 0.08, 2.1);
    float noiseB = randomNoise(worldXZ * 0.23, 5.7);
    float mask = radial + (noiseA - 0.5) * 0.6 + (noiseB - 0.5) * 0.4;
    return clamp(mask, 0.0, 1.0);
}

typedef struct
{
    float3 position [[attribute(VertexAttributePosition)]];
    float2 texCoord [[attribute(VertexAttributeTexcoord)]];
    float3 normal   [[attribute(VertexAttributeNormal)]];
} Vertex;

typedef struct
{
    float4 position [[position]];
    float2 texCoord;
    float3 worldNormal;
    float3 worldPos;
    float2 localXZ;
} ColorInOut;

vertex ColorInOut vertexShader(Vertex in [[stage_in]],
                               constant Uniforms & uniforms [[ buffer(BufferIndexUniforms) ]])
{
    ColorInOut out;

    float4 position = float4(in.position, 1.0);
    
    // Transform to clip space
    float4 modelPos = uniforms.modelViewMatrix * position;
    out.position = uniforms.projectionMatrix * modelPos;
    
    out.texCoord = in.texCoord;
    
    // Transform normal using normal matrix
    out.worldNormal = normalize(uniforms.normalMatrix * in.normal);
    
    // Calculate world position (from modelViewMatrix)
    out.worldPos = modelPos.xyz;
    out.localXZ = in.position.xz;

    return out;
}

fragment float4 fragmentShader(ColorInOut in [[stage_in]],
                               constant Uniforms & uniforms [[ buffer(BufferIndexUniforms) ]],
                               texture2d<float> colorTexture [[ texture(TextureIndexColor) ]],
                               texture2d<float> groundDirtTexture [[ texture(TextureIndexGround) ]])
{
    constexpr sampler linearSampler(coord::normalized,
                                    address::repeat,
                                    filter::linear);
    
    float3 baseColor = uniforms.baseColor.xyz;
    
    if (uniforms.materialType == MaterialTypeGround) {
        float2 chunkOrigin = uniforms.terrainWorld.xy;
        // worldXZ, skipMask, mask, and landBlend calculated but not used in current implementation
        // float2 worldXZ = chunkOrigin + in.localXZ;
        // bool skipMask = uniforms.terrainWorld.w > 0.5;
        // float mask = skipMask ? 1.0 : islandMask(worldXZ);
        // float landBlend = skipMask ? 1.0 : smoothstep(0.1, 0.35, mask);
        
        // Детальная текстура с вариацией UV для разнообразия
        float2 detailUV = float2(in.texCoord.x * uniforms.terrainUV.x,
                                 in.texCoord.y * uniforms.terrainUV.y) + uniforms.terrainUV.zw;
        detailUV += chunkOrigin * 0.02;
        
        // Используем только чистую текстуру terrain.jpg без дополнительных эффектов
        float3 texColor = groundDirtTexture.sample(linearSampler, in.texCoord).rgb;
        
        // Применяем только базовый цвет без покраски
        baseColor *= texColor;
    } else if (uniforms.materialType == MaterialTypeCharacter) {
        const float3 texColor = colorTexture.sample(linearSampler, in.texCoord).rgb;
        baseColor *= texColor;
    }
    
    // Улучшенное освещение с солнцем в центре карты (точечный источник)
    float3 normal = normalize(in.worldNormal);
    
    // Вычисляем направление к солнцу от текущей позиции
    float3 sunVec = uniforms.sunPosition - in.worldPos;
    float sunDistance = length(sunVec);
    float3 sunDir = sunVec / max(sunDistance, 0.0001);
    
    // Затухание света от солнца (attenuation)
    float sunAtten = 1.0;
    if (uniforms.sunRadius > 0.001) {
        // Квадратичное затухание для реалистичности
        float distRatio = sunDistance / uniforms.sunRadius;
        sunAtten = 1.0 / (1.0 + 0.09 * distRatio + 0.032 * distRatio * distRatio);
        sunAtten = clamp(sunAtten, 0.0, 1.0);
    }
    
    // Диффузное освещение от солнца
    float NdotL = max(dot(normal, sunDir), 0.0);
    
    // Окружающее освещение
    float3 ambient = uniforms.ambientColor;
    
    // Диффузное освещение от солнца с затуханием
    float3 diffuse = uniforms.lightColor * NdotL * sunAtten;
    
    // Спекулярное освещение (блики) для более реалистичного вида
    float3 viewDir = normalize(-in.worldPos); // Направление к камере
    float3 halfDir = normalize(sunDir + viewDir);
    float specPower = 32.0; // Сила блика
    float specIntensity = 0.3; // Интенсивность блика
    float specular = pow(max(dot(normal, halfDir), 0.0), specPower) * specIntensity;
    float3 specularLight = uniforms.lightColor * specular * sunAtten;
    
    // Комбинированное освещение от солнца
    float3 lighting = ambient + diffuse + specularLight;
    
    // Дополнительное освещение от героя (точечный источник)
    float3 heroVec = uniforms.heroLightPositionRadius.xyz - in.worldPos;
    float heroDistance = length(heroVec);
    float heroRadius = max(uniforms.heroLightPositionRadius.w, 0.001);
    float heroAtten = clamp(1.0 - heroDistance / heroRadius, 0.0, 1.0);
    if (heroAtten > 0.0) {
        float3 heroDir = heroVec / max(heroDistance, 0.0001);
        float heroDiffuse = max(dot(normal, heroDir), 0.0);
        float heroIntensity = uniforms.heroLightColorIntensity.w * heroAtten;
        float3 heroLighting = uniforms.heroLightColorIntensity.xyz * heroDiffuse * heroIntensity;
        lighting += heroLighting;
    }
    
    // Применяем освещение к цвету
    return float4(baseColor * lighting, uniforms.baseColor.w);
}
