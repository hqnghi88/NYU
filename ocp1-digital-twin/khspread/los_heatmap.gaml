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
		write "Step 4: Heatmap Ready. Blending is now bounded to province.";
	}
	
	// WEIGHTED BLENDING + ACTIVE RADIATION
	// Green actively pushes outward, Red stays passive
	reflex maintain_vibrancy {
		// 1. ACTIVE RADIATION: High-value sources push their color to nearby cells
		// Green pushes strongly, Orange moderately, Red barely
		ask heatmap_cell where (each.is_province and each.cell_value > 2.0) {
			// Higher values push harder: Green pushes to neighbors aggressively
			float my_val <- cell_value;
			list<heatmap_cell> weak_ns <- self.neighbors where (each.is_province and each.cell_value < my_val);
			ask weak_ns {
				// Push strength proportional to the source value
				float push <- my_val * 0.15;
				cell_value <- max([cell_value, cell_value * 0.5 + push]);
				// Cap at 6.0
				cell_value <- min([6.0, cell_value]);
			}
		}
		
		// 2. Weighted Blend for remaining empty cells
		ask heatmap_cell where (each.is_province and each.seed_value = 0.0 and each.cell_value < 0.1) {
			list<heatmap_cell> colored_ns <- self.neighbors where (each.is_province and each.cell_value > 0.1);
			if (!empty(colored_ns)) {
				float total_weight <- sum(colored_ns collect (each.cell_value * each.cell_value));
				float weighted_sum <- sum(colored_ns collect (each.cell_value * each.cell_value * each.cell_value));
				float weighted_avg <- weighted_sum / total_weight;
				cell_value <- weighted_avg * 0.5;
			}
		}
		
		// 3. Lock: Source cells always keep their original value
		ask heatmap_cell where (each.seed_value > 0) {
			cell_value <- seed_value;
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
		display "LOS Heatmap" type: 2d background: #white {
			// 1. Reliable Grid Display
			grid heatmap_cell border: #transparent;
			
			// 2. Reference Outlines
			species commune;
			
			// 3. Mask for professional results
			graphics "Ocean Mask" {
				draw mask_shape color: #white;
			}
			
			// 4. Detailed Status Legend
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
				draw "Status: " + (cycle < 100 ? "Blending..." : "Stable") at: {30 #px, (y_offset + 30) #px} color: #blue font: font("Arial", 9, #italic);
			}
		}
	}
}