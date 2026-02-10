# LOS Heatmap Development (Completed)

## Goal
The goal of this task was to create a high-quality visualization of the Level of Service (LOS) spread across Khanh Hoa province. The visualization needed to be visually smooth (gradient-like) rather than blocky, and include a dynamic 3D terrain representation.

## Key Features Implemented

### 1. Smooth 2D Gradient Blending
- Replaced discrete color blocks with continuous RGB interpolation.
- Implemented a custom `compute_color` action that blends between palette colors (Red -> Orange -> Yellow -> Green) based on fractional cell values (e.g., 3.5 creates a perfect mix of Orange and Yellow).

### 2. Stochastic Battle Mechanics (Green Expansion)
- Implemented a one-directional battle logic where high-value cells (Green/Good Service) actively conquer lower-value neighbors (Red/Poor Service).
- **Green Fortress**: Green source cells are anchored strongly efficiently (95% resistance to change).
- **Red Vulnerability**: Red source cells are weakly anchored (5% resistance) and easily flipped by nearby green influence.
- **Result**: A dynamic "green wave" that expands outward over time, simulating service improvement.

### 3. Optimized 3D "Cloud" Visualization
- Implemented a 3D terrain view using the `mesh` command for performance and smoothness.
- **Optimization Strategy**: While the logic runs on a `grid` species (for battle mechanics), the data is synced to a global `field` (`los_field`) every step. This allows the 3D display to render the pure field data efficiently.
- **Aesthetic**:
    - Calibrated `z_scaling` to **1.5%** of the map width to create gentle, rolling hills ("cloud-like") rather than steep spikes.
    - Added `transparency: 0.3` for an ethereal, professional look.
    - Used floating white boundaries to clearly delineate administrative districts above the color terrain.

## Files
- `los_heatmap.gaml`: The complete model file containing the grid logic, battle mechanics, and dual 2D/3D displays.
