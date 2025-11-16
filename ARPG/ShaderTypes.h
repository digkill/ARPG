//
//  ShaderTypes.h
//  ARPG
//
//  Created by Digkill on 15.11.2025.
//

//
//  Header containing types and enum constants shared between Metal shaders and Swift/ObjC source
//
#ifndef ShaderTypes_h
#define ShaderTypes_h

#ifdef __METAL_VERSION__
#define NS_ENUM(_type, _name) enum _name : _type _name; enum _name : _type
typedef metal::int32_t EnumBackingType;
#else
#import <Foundation/Foundation.h>
typedef NSInteger EnumBackingType;
#endif

#include <simd/simd.h>
#ifdef __METAL_VERSION__
// Metal doesn't need stdint.h
#else
#include <stdint.h>
#endif

typedef NS_ENUM(EnumBackingType, BufferIndex)
{
    BufferIndexMeshPositions = 0,
    BufferIndexMeshGenerics  = 1,
    BufferIndexUniforms      = 2
};

typedef NS_ENUM(EnumBackingType, VertexAttribute)
{
    VertexAttributePosition  = 0,
    VertexAttributeTexcoord  = 1,
    VertexAttributeNormal    = 2,
};

typedef NS_ENUM(EnumBackingType, TextureIndex)
{
    TextureIndexColor    = 0,
    TextureIndexGround   = 1,  // Текстура земли для смешивания
};

typedef NS_ENUM(EnumBackingType, MaterialType)
{
    MaterialTypeGround      = 0,
    MaterialTypeCharacter   = 1,
};

typedef struct
{
    matrix_float4x4 projectionMatrix;
    matrix_float4x4 modelViewMatrix;
    matrix_float3x3 normalMatrix;  // For lighting
    float time;
    vector_float3 lightDirection;  // Sun direction (normalized)
    vector_float3 lightColor;      // Sun color
    vector_float3 ambientColor;    // Ambient light color
    float padding0;
    vector_float4 baseColor;       // Base color/alpha for current draw
    MaterialType materialType;
    vector_float3 padding1;
    vector_float4 terrainUV;            // xy = detail scale, zw = detail offset
    vector_float4 terrainColorDetail;   // xyz = tint, w = detail intensity
    vector_float4 terrainWorld;         // xy = chunk origin (world), z = water level, w = reserved
} Uniforms;

#endif /* ShaderTypes_h */
