/**
* Name: LOSHeatmap
* Description: Stable Grid Heatmap with Bounded Diffusion.
* Built to prevent color loss and maintain vibrant smooth blending.
* Author: Antigravity
*/

model LOSHeatmap

global {
	// --- FILES ---
	file boundary_file <- file("khanh_hoa_communes.shp");
	file excel_data <- csv_file("Matlab.csv", ";");
	
	geometry shape <- envelope(boundary_file);
	
	map<string, rgb> los_colors <- [
		"A":: #green, "B":: #lawngreen, "C":: #yellow, "D":: #orange, "E":: #orangered, "F":: #red
	];
	
	map<string, float> los_numeric <- [
		"A":: 6.0, "B":: 5.0, "C":: 4.0, "D":: 3.0, "E":: 2.0, "F":: 1.0
	];

	geometry province_boundary;
	geometry mask_shape;
	float z_scaling <- 0.1;
	
	// FIELD for Mesh Visualization (Waterflow style)
	field los_field <- field(200, 200);

	init {
		write "Step 1: Loading Boundaries...";
		create commune from: boundary_file with: [province::string(read("NAME_1")), district::string(read("NAME_2")), commune_name::string(read("NAME_3"))];
		
		province_boundary <- union(commune collect each.shape);
		mask_shape <- shape - province_boundary;
		
		write "Step 2: Processing LOS Data...";
		matrix data <- matrix(excel_data);
		loop i from: 1 to: data.rows - 1 {
			string csv_xa <- lower_case(string(data[1, i]));
			string csv_huyen <- lower_case(string(data[4, i]));
			string v_los <- string(data[10, i]);
			
			ask commune where (
				(lower_case(each.commune_name) contains csv_xa or csv_xa contains lower_case(each.commune_name)) and
				(lower_case(each.district) contains csv_huyen or csv_huyen contains lower_case(each.district))
			) {
				los_value <- v_los;
			}
		}
		
		write "Step 3: Seeding Province Grid...";
		ask heatmap_cell {
			// Only cells inside the province are allowed to have color
			if (province_boundary overlaps self.location) {
				is_province <- true;
				commune xa <- first(commune overlapping self.location);
				if (xa != nil and xa.los_value != "") {
					seed_value <- los_numeric[xa.los_value];
					cell_value <- seed_value;
				}
			}
		}
		
		// Auto-calculate 3D height scale: 1.5% of width for "cloud" look
		z_scaling <- (shape.width * 0.015) / 6.0;
		
		// INITIAL SYNC: Make sure field has data before first frame!
		// INITIAL SYNC: Make sure field has data before first frame!
		ask heatmap_cell {
			los_field[grid_x, grid_y] <- cell_value;
		}
		
		write "Step 4: Heatmap and 3D Terrain Ready.";
	}
	
	// SYNC REFLEX: Update field from grid for 3D mesh
	reflex update_field {
		ask heatmap_cell {
			los_field[grid_x, grid_y] <- cell_value;
		}
	}
	
	// ONE-DIRECTIONAL BATTLE: Only higher values attack lower
	// Red can NEVER attack Green. Green ALWAYS expands.
	reflex color_battle {
		// 1. EXPANSION: Each cell pushes its color to ALL weaker neighbors
		// Higher values push more aggressively
		ask heatmap_cell where (each.is_province and each.cell_value > 1.5) {
			float my_val <- cell_value;
			// Push strength: Green pushes hard, Orange moderate
			float push_strength <- (my_val / 6.0) * 0.5;  // Green=0.5, Red=0.08
			ask self.neighbors where (each.is_province and each.cell_value < my_val) {
				// Stochastic: random chance to convert (higher values = higher chance)
				if (flip(push_strength)) {
					// Convert! Pull strongly toward attacker's value
					cell_value <- cell_value * 0.3 + my_val * 0.7;
				}
			}
		}
		
		// 2. Source anchoring: Green anchors hard, Red barely
		ask heatmap_cell where (each.seed_value > 0) {
			float anchor <- (seed_value / 6.0);
			anchor <- anchor * anchor * anchor;  // Red=0.005, Green=1.0
			float pull <- 0.05 + anchor * 0.9;   // Red=0.05, Green=0.95
			cell_value <- cell_value * (1.0 - pull) + seed_value * pull;
		}
		
		// 3. Floor: keep everything visible
		ask heatmap_cell where (each.is_province and each.cell_value < 0.5) {
			cell_value <- 0.5;
		}
	}
}

// Fixed Grid for performance and reliability
grid heatmap_cell width: 200 height: 200 {
	float cell_value <- 0.0;
	float seed_value <- 0.0;
	bool is_province <- false;
	
	// Smooth color interpolation with proper gradient
	action compute_color {
		if (cell_value < 0.1) {
			color <- #white;
		} else {
			// Clamp to [1.0, 6.0] for palette lookup
			float v <- min([6.0, cell_value]);
			
			// For values between 0.1 and 1.0: fade from white to red
			if (v < 1.0) {
				int r <- int(255 * v);
				int g <- int(255 * (1.0 - v));
				int b <- int(255 * (1.0 - v));
				color <- rgb(r, g, b);
			} else {
				// Palette stops: 1=Red, 2=OrangeRed, 3=Orange, 4=Yellow, 5=LawnGreen, 6=Green
				list<rgb> p <- [#red, #orangered, #orange, #yellow, #lawngreen, #green];
				
				// Find the two colors to blend between
				int lo <- min([4, int(v) - 1]);  // lower index (0-based)
				int hi <- min([5, lo + 1]);      // upper index (capped)
				float frac <- v - int(v);         // fractional part
				
				// Linear RGB interpolation
				rgb c1 <- p[lo];
				rgb c2 <- p[hi];
				int r <- int(c1.red + (c2.red - c1.red) * frac);
				int g <- int(c1.green + (c2.green - c1.green) * frac);
				int b <- int(c1.blue + (c2.blue - c1.blue) * frac);
				color <- rgb(r, g, b);
			}
		}
	}
	
	reflex update_my_color {
		do compute_color;
	}
	
	aspect default {
		draw shape color: color;
	}
	
	aspect threeD {
		if (cell_value > 0.1) {
			draw box(shape.width, shape.height, cell_value * z_scaling) color: color;
		}
	}
}

species commune {
	string province;
	string district;
	string commune_name;
	string los_value <- "";
	aspect default {
		draw shape color: #transparent border: rgb(50, 50, 50, 20) width: 0.5;
	}
}

experiment LOSHeatmap type: gui {
	output {
		// 2D View
		display "LOS Heatmap" type: 2d background: #white {
			grid heatmap_cell border: #transparent;
			species commune;
			graphics "Ocean Mask" {
				draw mask_shape color: #white;
			}
			overlay position: {0, 0} size: {220 #px, 320 #px} background: #white border: #black {
				draw "LOS Surface Map" at: {20 #px, 30 #px} color: #black font: font("Arial", 12, #bold);
				int y_offset <- 60;
				loop l over: ["A", "B", "C", "D", "E", "F"] {
					draw square(15 #px) at: {30 #px, (y_offset) #px} color: los_colors[l];
					draw "LOS " + l at: {55 #px, (y_offset + 12) #px} color: #black font: font("Arial", 11, #plain);
					y_offset <- y_offset + 30;
				}
				float max_v <- max(heatmap_cell collect each.cell_value);
				draw "Intensity: " + string(int(max_v * 10) / 10.0) at: {30 #px, (y_offset + 10) #px} color: (max_v > 0.5 ? #darkgreen : #red);
			}
		}
		
		// 3D Terrain View — MESH Optimized (like Waterflow example)
		display "LOS 3D Terrain" type: opengl background: #white {
			// Mesh draws the FIELD directly (fast & smooth) WITH Transparency for "cloud" look
			mesh los_field scale: z_scaling triangulation: true smooth: true transparency: 0.3
				color: palette([#white, #red, #orangered, #orange, #yellow, #lawngreen, #green])
				no_data: -1.0; // Draw everything, even 0.0 values
			
			overlay position: {0, 0} size: {220 #px, 320 #px} background: #white border: #black {
				draw "LOS Surface Map" at: {20 #px, 30 #px} color: #black font: font("Arial", 12, #bold);
				int y_offset <- 60;
				loop l over: ["A", "B", "C", "D", "E", "F"] {
					draw square(15 #px) at: {30 #px, (y_offset) #px} color: los_colors[l];
					draw "LOS " + l at: {55 #px, (y_offset + 12) #px} color: #black font: font("Arial", 11, #plain);
					y_offset <- y_offset + 30;
				}
				float max_v <- max(heatmap_cell collect each.cell_value);
				draw "Intensity: " + string(int(max_v * 10) / 10.0) at: {30 #px, (y_offset + 10) #px} color: (max_v > 0.5 ? #darkgreen : #red);
			}
			// Floating borders
//			graphics "Floating Borders" {
//				float float_h <- 6.0 * (z_scaling * 5) * 1.05;
//				loop c over: commune {
//					draw c.shape color: #transparent border: #white width: 2.0 at: {0, 0, float_h};
//				}
//			}
		}
	}
}