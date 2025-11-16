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

constant float kGroundBaseUVScale = 0.05;
constant float kIslandRadius = 120.0;
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
        float2 worldXZ = chunkOrigin + in.localXZ;
        bool skipMask = uniforms.terrainWorld.w > 0.5;
        float mask = skipMask ? 1.0 : islandMask(worldXZ);
        float landBlend = skipMask ? 1.0 : smoothstep(0.1, 0.35, mask);
        
        // Основная текстура террейна (фантазийная)
        float3 baseSample = colorTexture.sample(linearSampler, in.texCoord).rgb;
        
        // Детальная текстура с вариацией UV для разнообразия
        float2 detailUV = float2(in.texCoord.x * uniforms.terrainUV.x,
                                 in.texCoord.y * uniforms.terrainUV.y) + uniforms.terrainUV.zw;
        detailUV += chunkOrigin * 0.02;
        float3 detailSample = colorTexture.sample(linearSampler, detailUV).rgb;
        
        // Улучшенный блендинг базовой и детальной текстуры
        float blendFactor = 0.6; // Больше веса базовой текстуре
        float3 fantasyTexColor = mix(detailSample, baseSample, blendFactor);
        
        // Текстура земли для смешивания (если доступна и не белая)
        float3 texColor = fantasyTexColor; // По умолчанию используем только фантазийную текстуру
        
        // Вычисляем worldXZ для использования в магических эффектах и смешивании
        float2 worldUVCoords = in.texCoord / kGroundBaseUVScale;
        
        // Пытаемся смешать с землей, но только если это не белая текстура-заглушка
        float3 dirtSample = groundDirtTexture.sample(linearSampler, in.texCoord).rgb;
        // Проверяем, не является ли это белой текстурой (белый цвет ≈ 1.0, 1.0, 1.0)
        // Используем проверку яркости - если очень близко к белому, значит это заглушка
        float dirtBrightness = length(dirtSample);
        if (dirtBrightness < 2.8 && landBlend > 0.05) { // Если не белая текстура (белый = ~3.0), смешиваем
            float3 dirtDetailSample = groundDirtTexture.sample(linearSampler, detailUV).rgb;
            float3 dirtTexColor = mix(dirtDetailSample, dirtSample, blendFactor);
            
            // Смешивание фантазийной текстуры и земли на основе процедурного шума
            float dirtBlendNoise = fract(sin(dot(worldUVCoords, float2(23.1407, 2.6651))) * 43758.5453);
            // Создаем паттерн для смешивания - больше земли в определенных областях
            float dirtBlendFactor = smoothstep(0.3, 0.7, dirtBlendNoise) * 0.4; // Максимум 40% земли
            texColor = mix(fantasyTexColor, dirtTexColor, dirtBlendFactor);
        }
        
        // Процедурный шум для вариации цвета
        float detailNoise = fract(sin(dot(detailUV, float2(12.9898, 78.233))) * 43758.5453);
        float detailIntensity = uniforms.terrainColorDetail.w;
        float detailFactor = 1.0 + (detailNoise - 0.5) * 2.0 * detailIntensity;
        texColor *= uniforms.terrainColorDetail.xyz * detailFactor;
        
        // Магические эффекты для фантазийного мира
        
        // Создаем волнообразный магический паттерн
        float magicWave = sin(worldUVCoords.x * 0.3 + uniforms.time * 0.5) * 
                         cos(worldUVCoords.y * 0.3 + uniforms.time * 0.3) * 0.5 + 0.5;
        float3 magicTint = float3(0.7, 0.9, 1.0); // Светло-голубой магический оттенок
        float magicStrength = 0.15; // Сила магического эффекта
        texColor = mix(texColor, texColor * magicTint, magicWave * magicStrength);
        
        // Добавляем легкое свечение на определенных участках
        float glowPattern = sin(worldUVCoords.x * 0.5) * sin(worldUVCoords.y * 0.5);
        if (glowPattern > 0.7) {
            float3 glowColor = float3(0.8, 1.0, 0.9); // Светло-зеленое свечение
            texColor = mix(texColor, texColor * glowColor, (glowPattern - 0.7) * 0.3);
        }
        
        // Тонкая сетка для визуальной ориентации (более тонкая для фантазийного мира)
        const float gridSize = 4.0;
        const float gridThickness = 0.02; // Более тонкие линии
        float2 gridCoord = fract((worldXZ / gridSize) + 1000.0);
        float lineX = 1.0 - smoothstep(0.0, gridThickness, min(gridCoord.x, 1.0 - gridCoord.x));
        float lineY = 1.0 - smoothstep(0.0, gridThickness, min(gridCoord.y, 1.0 - gridCoord.y));
        float gridMix = max(lineX, lineY);
        // Более мягкий цвет сетки для фантазийного мира
        float3 gridColor = float3(0.12, 0.15, 0.18); // Темно-синеватый
        texColor = mix(texColor, gridColor, gridMix * 0.4 * landBlend);
        
        float3 waterColor = float3(0.05, 0.13, 0.22);
        float foam = skipMask ? 0.0 : smoothstep(0.08, 0.2, mask) * (1.0 - smoothstep(0.35, 0.55, mask));
        float3 coastFoamColor = float3(0.9, 0.97, 1.0);
        texColor = mix(waterColor, texColor, landBlend);
        texColor = mix(coastFoamColor, texColor, 1.0 - foam * 0.8);
        
        // Финальная коррекция цвета для более насыщенного фантазийного вида
        texColor = pow(texColor, float3(0.95)); // Легкое повышение контраста
        
        baseColor *= texColor;
    } else if (uniforms.materialType == MaterialTypeCharacter) {
        const float3 texColor = colorTexture.sample(linearSampler, in.texCoord).rgb;
        baseColor *= texColor;
    }
    
    // Apply simple lighting
    float3 normal = normalize(in.worldNormal);
    float3 lightDir = normalize(uniforms.lightDirection);
    float NdotL = max(dot(normal, lightDir), 0.0);
    
    float3 ambient = uniforms.ambientColor;
    float3 diffuse = uniforms.lightColor * NdotL;
    float3 lighting = ambient + diffuse;
    
    // Apply lighting to color
    return float4(baseColor * lighting, uniforms.baseColor.w);
}
