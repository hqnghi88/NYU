/**
* Name: OCPMap2
* Author: ADMIN
* Tags: osm, map, visualization, 3d, google_maps
*/
model OCPMap2

global {
	// --- GLOBAL PARAMETERS ---
	float step <- 1.0 #s;
	field cell <- field(300, 300);
	list<rgb> pal <- palette([#black, #green, #yellow, #orange, #orange, #red, #red, #red]);

	// Scenarios: 0 = Capacity/Ratios, 1 = Signals & Compliance, 2 = Mixed/Chaos
	int scenario_type <- 0;
	
	// Files
	file map_osm_file <- osm_file("../includes/map (2).osm");
	geometry shape <- envelope(map_osm_file);
	graph road_network;

	init {
		write "Step 1: Reading file...";
		list<geometry> osm_shapes <- map_osm_file.contents;
		
		write "Step 2: Processing Agents...";
		loop geom over: osm_shapes {
			create osm_agent {
				shape <- geom;
			}
		}

		write "Step 3: Building the City...";
		ask osm_agent {
			map<string, unknown> atts <- shape.attributes;

			// --- A. ROADS ---
			if (atts contains_key "highway") {
				create road {
					shape <- myself.shape;
					type <- string(atts["highway"]);
					
					// Define width and capacity based on type
					if (type in ["primary", "trunk", "motorway"]) {
						color <- #orange;
						width <- 10.0;
						num_lanes <- 4;
					} else if (type in ["secondary", "tertiary"]) {
						color <- #white;
						width <- 7.0;
						num_lanes <- 2;
					} else {
						color <- #white;
						width <- 4.0;
						num_lanes <- 1;
					}
				}
			}

			// --- B. BUILDINGS ---
			if (atts contains_key "building") {
				create building {
					shape <- myself.shape;
					if (atts contains_key "building:levels") {
						height <- float(atts["building:levels"]) * 3.5;
					} else {
						height <- rnd(8.0, 20.0);
					}
					if (atts contains_key "name" and ("S2" in string(atts["name"]))) {
						is_S2 <- true;
					}
				}
			}

			// --- C. NATURE ---
			if (atts contains_key "natural" or atts contains_key "waterway" or atts contains_key "landuse" or atts contains_key "leisure") {
				create nature {
					shape <- myself.shape;
					if (atts["natural"] = "water" or atts["waterway"] != nil) {
						type <- "water";
						color <- #dodgerblue;
					} else if (atts["landuse"] = "grass" or atts["leisure"] = "park" or atts["landuse"] = "forest") {
						type <- "green";
						color <- #honeydew;
						int nb_trees <- int(shape.area / 100.0);
						if (nb_trees > 0 and nb_trees < 500) {
							create tree number: nb_trees {
								location <- any_location_in(myself.shape);
							}
						}
					} else {
						type <- "generic";
						color <- #gainsboro;
					}
				}
			}
			do die;
		}

		// --- TRAFFIC NETWORK ---
		road_network <- as_edge_graph(road);
		
		// --- INTERSECTIONS & SIGNALS ---
		// Create traffic lights at nodes with > 2 connections
		list<point> nodes <- road_network.vertices;
		loop n over: nodes {
			if (length(road_network out_edges_of n) > 2) {
				create traffic_light {
					location <- n;
				}
			}
		}

		// --- AGENT GENERATION ---
		do spawn_agents;
		
		// --- POLICE ---
		if (scenario_type = 1 and !empty(traffic_light)) {
			create traffic_police number: 2 {
				location <- one_of(traffic_light).location;
			}
		}
	}
	
	action spawn_agents {
		if (!empty(road)) {
			// Ratios based on Scenario 0 (or default)
			int nb_cars <- 50;
			int nb_motorbikes <- 50;
			int nb_buses <- 5;
			
			if (scenario_type = 0) {
				// Scenario 1: Split capacities / Fixed ratios
				nb_cars <- 40;
				nb_motorbikes <- 80;
			}
			
			create car number: nb_cars {
				location <- any_location_in(one_of(road));
			}
			create motorbike number: nb_motorbikes {
				location <- any_location_in(one_of(road));
			}
			create bus number: nb_buses {
				location <- any_location_in(one_of(road));
			}
			create pedestrian number: 50 {
				location <- any_location_in(one_of(road)); // Simplification: Pedestrians on road graph for now
			}
		}

		// S2 Trucks
		list<building> s2_buildings <- building where (each.is_S2);
		if (length(s2_buildings) > 0) {
			create truck number: 5 {
				location <- any_location_in(one_of(s2_buildings).shape);
			}
		}
	}

	reflex pollution_evolution {
		// Diffuse the pollution values in the field
		diffuse var: cell on: cell proportion: 0.8;
	}
}

// --- ENVIRONMENT AGENTS ---

species osm_agent {}

species nature {
	string type;
	rgb color;
	reflex shimmer when: type = "water" { color <- rgb(30, 144, 255, 200 + rnd(50)); }
	aspect default { draw shape color: color border: #white; }
}

species tree {
	float size <- rnd(2.0, 5.0);
	aspect default {
		draw cylinder(size / 4, size) color: #saddlebrown at: {location.x, location.y, 0};
		draw sphere(size) color: #forestgreen at: {location.x, location.y, size};
	}
}

species building {
	float height;
	bool is_S2 <- false;
	aspect default { draw shape color: (is_S2 ? #gold : #whitesmoke) border: #lightgray depth: height; }
}

species road {
	string type;
	rgb color;
	float width;
	int num_lanes <- 1;
	aspect default { draw shape color: color width: width at: {location.x, location.y, 0.1}; }
}

species traffic_light {
	bool is_green <- flip(0.5);
	int counter <- rnd(10, 30);
	
	reflex cycle when: (scenario_type = 1) { // Only active in Scenario 2 (Signals)
		counter <- counter - 1;
		if (counter <= 0) {
			is_green <- !is_green;
			counter <- rnd(20, 40);
		}
	}
	
	aspect default {
		if (scenario_type = 1) {
			draw sphere(3) color: (is_green ? #green : #red) at: {location.x, location.y, 5};
		}
	}
}

species traffic_police {
	aspect default {
		draw pyramid(4) color: #blue at: {location.x, location.y, 2};
		draw sphere(1) color: #yellow at: {location.x, location.y, 6};
	}
}

// --- MOVING AGENTS ---

species pedestrian skills: [moving] {
	point target;
	float speed <- rnd(2.0, 5.0) #km/#h;
	
	reflex move {
		if (target = nil) { target <- any_location_in(one_of(building)); }
		do goto target: target on: road_network speed: speed;
		if (location distance_to target < 2.0) { target <- nil; }
	}
	
	aspect default { draw cylinder(0.5, 1.8) color: #pink; }
}

species vehicle skills: [moving] {
	point target;
	float speed;
	float max_speed;
	float compliance_level <- 1.0; // Individual compliance
	float lane_offset <- 0.0;
	
	init {
		if (scenario_type = 1) {
			// Scenario 2: Compliance Levels (20%, 40%, 60%)
			compliance_level <- one_of([0.2, 0.4, 0.6, 1.0]); 
		} else if (scenario_type = 2) {
			compliance_level <- 0.0; // Mixed/Chaos
		}
	}

	reflex define_target when: target = nil {
		target <- any_location_in(one_of(building));
	}

	action check_traffic_lights {
		if (scenario_type != 1) { return; } // Only obey in Scenario 2
		
		traffic_light close_light <- traffic_light closest_to self;
		if (close_light != nil and (location distance_to close_light < 15.0)) {
			if (!close_light.is_green) {
				// Check compliance
				if (flip(compliance_level)) {
					speed <- 0.0; // Stop
				} else {
					// Violation!
				}
			} else {
				speed <- max_speed;
			}
		} else {
			speed <- max_speed;
		}
	}
	
	reflex move {
		do check_traffic_lights();
		
		if (speed > 0) {
			path path_followed <- goto(target: target, on: road_network, speed: speed, return_path: true);
			if (path_followed != nil and path_followed.shape != nil) {
				cell[path_followed.shape.location] <- cell[path_followed.shape.location] + 5;					
			}
		}
		
		if (target != nil and location distance_to target < 5.0) {
			target <- nil;
		}
	}
}

species car parent: vehicle {
	init { 
		max_speed <- rnd(30.0, 70.0) #km/#h; 
		speed <- max_speed;
		lane_offset <- 1.5; // Right lane
	}
	aspect default { 
		draw box(2, 4, 2) color: #crimson rotate: heading; 
	}
}

species motorbike parent: vehicle {
	init { 
		max_speed <- rnd(40.0, 80.0) #km/#h; 
		speed <- max_speed;
		lane_offset <- 0.5;
	}
	aspect default { draw box(1, 2, 1.5) color: #purple rotate: heading; }
}

species bus parent: vehicle {
	init { 
		max_speed <- rnd(20.0, 50.0) #km/#h; 
		speed <- max_speed;
	}
	aspect default { draw box(3, 8, 3) color: #cyan rotate: heading; }
}

species truck parent: vehicle { // S2 trucks
	init { 
		max_speed <- rnd(30.0, 60.0) #km/#h; 
		speed <- max_speed;
	}
	aspect default { draw box(3, 6, 3) color: #blue rotate: heading; }
}


// --- EXPERIMENT ---

experiment OCPMap2 type: gui {
	// Add inputs for scenarios
	parameter "Scenario (0:Ratio, 1:Signal, 2:Chaos)" category: "Scenarios" var: scenario_type min: 0 max: 2;
	
	output {
		display "Google Maps 3D" type: 3d background: #lightskyblue axes: false {
			species nature refresh:false;
			species road refresh:false;
			species tree refresh:false;
			species building refresh:false;
			
			species traffic_light;
			species traffic_police;
			
			species pedestrian;
			species car;
			species motorbike;
			species bus;
			species truck;
			
			mesh cell scale: 9 triangulation: true transparency: 0.4 smooth: 3 above: 0.8 color: pal;
		}
		
		// Optional: Charts for analysis
		display "Traffic Info" {
			chart "Active Agents" type: series {
				data "Cars" value: length(car);
				data "Bikes" value: length(motorbike);
				data "Pollution" value: mean(cell collect each); // Valid way to get mean of field
			}
		}
	}
}