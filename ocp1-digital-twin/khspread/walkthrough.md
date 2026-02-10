# LOS Heatmap Walkthrough

## Overview

The `los_heatmap.gaml` model simulates the spread of Level of Service (LOS) quality across Khanh Hoa province. It is designed to visualize how "Good Service" (Green/LOS A) can overcome "Poor Service" (Red/LOS F) over time, creating a dynamic battle for territory. It includes both a smooth 2D heatmap and a stunning 3D terrain visualization.

## Core Logic

### 1. Grid vs. Field
The model uses a hybrid approach for maximum flexibility and performance:
- **Grid Species (`heatmap_cell`)**: Handles the complex battle logic. Each cell interacts with its neighbors (8-neighborhood) to calculate influence.
- **Global Field (`los_field`)**: A parallel data structure that simply stores the `cell_value` for visualization. This allows the 3D display to use the highly optimized `mesh` command, which renders fields much faster and smoother than individually drawing thousands of grid cells.

### 2. Stochastic Battle Mechanics (Green Wins)
The model implements a "one-directional battle" where higher values always attack lower values:
- **Green (6.0)**: Attacks all 8 neighbors with a **50% conversion chance** per step. Neighbors are pulled 70% toward the attacker's value.
- **Red (1.0)**: Cannot attack. It can only defend, but its defense is weak (5% anchor strength).
- **Result**: Green areas expand outward like a wave, conquering red territory over time. Red areas shrink and are eventually overcome.

### 3. Smooth Color Blending
Instead of discrete color blocks (which look pixelated), the model uses a custom `compute_color` action:
- It defines a palette: Red (1.0) -> Orange (3.0) -> Yellow (4.0) -> Green (6.0).
- For any fractional value (e.g., 3.5), it calculates a weighted average of the two nearest colors (50% Orange + 50% Yellow). This creates smooth, professional gradients.

## Visualization

### 3D "Cloud" Terrain
The 3D view is designed to look like a floating, ethereal cloud layer rather than a jagged mountain range:
- **Z-Scaling**: The height of the terrain is dynamically calculated as **1.5%** of the map width. This creates gentle, rolling hills.
- **Transparency**: The mesh uses `transparency: 0.3` to allow some light to pass through, enhancing the "cloud" effect.
- **Synchronization**: A reflex `update_field` runs every step to copy the latest grid values into `los_field`, ensuring the 3D view is always up-to-date with the battle.

### Troubleshooting "Black Screen" in Mesh
During development, the `mesh` command initially rendered as black.
- **Cause**: The `mesh` command in GAMA requires a `palette` (list of colors) to map values to colors. We were incorrectly using `color: scale(...)` which is for 2D drawing.
- **Fix**: Changed to `color: palette([#white, #red, ... #green])` and ensured the field was populated in the `init` block before the first frame was drawn.

## Future Extensions
- **Interactive Obstacles**: Add agents that block the spread (e.g., mountains, no-service zones).
- **Time-Series Data**: Load new LOS data from CSV files at specific simulation ticks to animate changing conditions over time.
