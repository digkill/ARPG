#!/usr/bin/env python3
"""
Генератор процедурной текстуры террейна для фантазийного мира
Создает текстуру с комбинацией травы, земли, камней и магических элементов
"""

from PIL import Image, ImageDraw, ImageFilter
import numpy as np
import math

def generate_fantasy_terrain(size=2048):
    """
    Генерирует текстуру террейна для фантазийного мира
    Размер: 2048x2048 пикселей (можно изменить)
    """
    # Создаем базовое изображение
    img = Image.new('RGB', (size, size))
    pixels = img.load()
    
    # Цвета для фантазийного террейна
    grass_dark = (45, 80, 35)      # Темная трава
    grass_light = (85, 140, 65)    # Светлая трава
    dirt_brown = (90, 70, 50)      # Коричневая земля
    dirt_dark = (60, 45, 35)       # Темная земля
    stone_gray = (100, 100, 110)   # Серый камень
    stone_light = (130, 130, 140)  # Светлый камень
    magic_blue = (70, 100, 150)    # Магический синий оттенок
    moss_green = (60, 100, 70)     # Зеленый мох
    
    # Генерируем процедурный шум для разнообразия
    noise_scale = 0.1
    for y in range(size):
        for x in range(size):
            # Процедурный шум для определения типа поверхности
            nx = x * noise_scale
            ny = y * noise_scale
            
            # Используем несколько слоев шума для естественного вида
            noise1 = math.sin(nx * 0.5) * math.cos(ny * 0.5)
            noise2 = math.sin(nx * 1.2 + ny * 0.8) * 0.5
            noise3 = math.sin(nx * 2.1 - ny * 1.5) * 0.3
            combined_noise = noise1 + noise2 + noise3
            
            # Нормализуем шум к диапазону 0-1
            normalized_noise = (combined_noise + 3) / 6.0
            normalized_noise = max(0.0, min(1.0, normalized_noise))
            
            # Определяем тип поверхности на основе шума
            if normalized_noise < 0.3:
                # Темная трава/земля
                base_color = grass_dark
                variation = normalized_noise / 0.3
                color = tuple(int(base_color[i] + (dirt_dark[i] - base_color[i]) * variation) for i in range(3))
            elif normalized_noise < 0.5:
                # Светлая трава
                base_color = grass_light
                variation = (normalized_noise - 0.3) / 0.2
                color = tuple(int(grass_dark[i] + (base_color[i] - grass_dark[i]) * variation) for i in range(3))
            elif normalized_noise < 0.7:
                # Камни
                base_color = stone_gray
                variation = (normalized_noise - 0.5) / 0.2
                color = tuple(int(stone_gray[i] + (stone_light[i] - stone_gray[i]) * variation) for i in range(3))
            else:
                # Магические элементы (светлые участки)
                base_color = magic_blue
                variation = (normalized_noise - 0.7) / 0.3
                # Смешиваем с травой для плавного перехода
                grass_mix = tuple(int(grass_light[i] * (1 - variation) + base_color[i] * variation) for i in range(3))
                color = grass_mix
            
            # Добавляем мелкие детали (камешки, травинки)
            detail_noise = math.sin(nx * 5.0) * math.cos(ny * 5.0)
            if abs(detail_noise) > 0.7:
                # Добавляем темные точки (камни, тени)
                color = tuple(max(0, c - 15) for c in color)
            elif abs(detail_noise) < 0.2:
                # Добавляем светлые точки (свет, блики)
                color = tuple(min(255, c + 10) for c in color)
            
            pixels[x, y] = color
    
    # Применяем размытие для более естественного вида
    img = img.filter(ImageFilter.GaussianBlur(radius=1))
    
    # Добавляем текстуру мха и детали
    draw = ImageDraw.Draw(img)
    for _ in range(100):  # Добавляем случайные пятна мха
        x = np.random.randint(0, size)
        y = np.random.randint(0, size)
        radius = np.random.randint(20, 60)
        # Рисуем эллипс мха
        draw.ellipse([x-radius, y-radius, x+radius, y+radius], 
                    fill=moss_green, outline=None)
    
    # Применяем финальное размытие для плавности
    img = img.filter(ImageFilter.GaussianBlur(radius=0.5))
    
    return img

if __name__ == "__main__":
    print("Генерация текстуры фантазийного террейна...")
    terrain = generate_fantasy_terrain(2048)
    
    # Сохраняем в несколько мест
    import os
    script_dir = os.path.dirname(os.path.abspath(__file__))
    project_root = os.path.dirname(os.path.dirname(script_dir))
    
    output_paths = [
        os.path.join(script_dir, "FantasyTerrain.png"),
        os.path.join(project_root, "Assets.xcassets", "FantasyTerrain.textureset", "Universal.mipmapset", "FantasyTerrain.png")
    ]
    
    for path in output_paths:
        # Создаем директорию если нужно
        os.makedirs(os.path.dirname(path), exist_ok=True)
        terrain.save(path)
        print(f"✅ Текстура сохранена: {path}")
    
    print("✅ Генерация завершена!")
    print("\nДля использования:")
    print("1. Убедитесь, что FantasyTerrain.png находится в Assets.xcassets/FantasyTerrain.textureset/Universal.mipmapset/")
    print("2. Перезапустите Xcode проект")

