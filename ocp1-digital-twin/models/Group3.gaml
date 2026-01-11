/**
* Name: OCPMap2
* Author: ADMIN
* Tags: osm, map, visualization, 3d, google_maps
*/
model OCPMap2

global {
	// --- 1. SCENARIO PARAMETERS ---
	bool motorbike_ban <- false;
	bool metro_active <- false;
	float subway_capacity <- 0.1 min: 0.0 max: 1.0;
	
	// Emission Factors
	float emission_car <- 10.0;
	float emission_bike <- 5.0;
	float emission_bus <- 15.0; // Per vehicle, but carries more people
	float emission_ev <- 0.0;

	// --- 2. ENVIRONMENT ---
	float step <- 0.5 #s; // Slightly faster step for smoother traffic
	// 'cell' is now a grid species defined below
	list<rgb> pal <- palette([#black, #green, #yellow, #orange, #orange, #red, #red, #red]);
	
	// Tracking Metrics
	float total_pollution -> cell sum_of (each.grid_value);

	// --- 3. FILES ---
	file map_osm_file <- osm_file("../includes/g3.osm");
	geometry shape <- envelope(map_osm_file);
	graph road_network;

	init {
		write "Step 1: Reading file...";
		list<geometry> osm_shapes <- map_osm_file.contents;
		write "Step 2: Processing Agents...";
		
		// Parse OSM Data
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
					if (type in ["primary", "trunk", "motorway"]) {
						color <- #orange;
						width <- 10.0;
					} else if (type in ["secondary", "tertiary"]) {
						color <- #white;
						width <- 7.0;
					} else {
						color <- #white;
						width <- 4.0;
					}
				}
			}

			// --- B. BUILDINGS ---
			if (atts contains_key "building") {
				create building {
					shape <- myself.shape;
					// height
					if (atts contains_key "building:levels") {
						height <- float(atts["building:levels"]) * 3.5;
					} else {
						height <- rnd(8.0, 20.0);
					}
					// Detect S2 buildings
					if (atts contains_key "name" and ("S2" in string(atts["name"]))) {
						is_S2 <- true;
					}
				}
			}

			// --- C. NATURE & TREES ---
			if (atts contains_key "natural" or atts contains_key "waterway" or atts contains_key "landuse" or atts contains_key "leisure") {
				create nature {
					shape <- myself.shape;
					// WATER
					if (atts["natural"] = "water" or atts["waterway"] != nil) {
						type <- "water";
						color <- #dodgerblue;
					}
					// GREEN ZONES
					else if (atts["landuse"] = "grass" or atts["leisure"] = "park" or atts["landuse"] = "forest") {
						type <- "green";
						color <- #honeydew;
						// PLANT TREES
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

		// --- TRAFFIC GENERATION LOGIC ---
		road_network <- as_edge_graph(road);
		
		if (!empty(road)) {
			// Base counts
			int base_cars <- 60;
			int base_bikes <- 100;
			int base_buses <- 5;
			int base_evs <- 10;

			// Apply Scenarios
			// 1. Metro Impact: Reduces private vehicles based on capacity
			float reduction_factor <- metro_active ? (subway_capacity * 0.8) : 0.0; // Max 80% reduction if capacity is full
			
			int final_cars <- int(base_cars * (1 - reduction_factor));
			int final_bikes <- int(base_bikes * (1 - reduction_factor));
			int final_evs <- int(base_evs * (1 - reduction_factor)); // EVs also reduced by metro? Assuming yes.

			// 2. Motorbike Ban
			if (motorbike_ban) {
				final_bikes <- 0;
			}

			write "Spawning agents: " + final_cars + " Cars, " + final_bikes + " Bikes, " + base_buses + " Buses";

			// SPAWN CARS
			create car number: final_cars {
				location <- any_location_in(one_of(road));
				speed <- rnd(30.0, 70.0) #km / #h;
			}
			
			// SPAWN MOTORBIKES
			create motorbike number: final_bikes {
				location <- any_location_in(one_of(road));
				speed <- rnd(40.0, 80.0) #km / #h; // Agile
			}
			
			// SPAWN BUSES
			create bus number: base_buses {
				location <- any_location_in(one_of(road));
				speed <- rnd(20.0, 50.0) #km / #h;
			}
			
			// SPAWN EVs
			create ev_vehicle number: final_evs {
				location <- any_location_in(one_of(road));
				speed <- rnd(30.0, 70.0) #km / #h;
			}
		}

		// --- SPAWN TRUCK(S) ---
		list<building> s2_buildings <- building where (each.is_S2);
		if (length(s2_buildings) > 0) {
			create truck number: 5 {
				location <- any_location_in(one_of(s2_buildings).shape);
			}
		}
	}

	//Reflex to decrease and diffuse the pollution of the environment
	reflex pollution_evolution {
		//diffuse the pollutions to neighbor cells
		diffuse var: grid_value on: cell proportion: 0.8;
		//Natural decay
		ask cell {
			grid_value <- grid_value * 0.9;
		}
	}
}

// --- SPECIES ---
species osm_agent { }

species nature {
	string type;
	rgb color;
	reflex shimmer when: type = "water" {
		color <- rgb(30, 144, 255, 200 + rnd(50));
	}
	aspect default {
		draw shape color: color border: #white;
	}
}

species tree {
	float size <- rnd(2.0, 5.0);
	aspect default {
		draw cylinder(size / 4, size) color: #saddlebrown at: {location.x, location.y, 0};
		draw sphere(size) color: #forestgreen at: {location.x, location.y, size};
	}
}

species road {
	string type;
	rgb color;
	float width;
	aspect default {
		draw shape color: color width: width at: {location.x, location.y, 0.1};
	}
}

species building {
	float height;
	bool is_S2 <- false;
	aspect default {
		draw shape color: (is_S2 ? #gold : #whitesmoke) border: #lightgray depth: height;
	}
}

// Parent species for common traffic behavior
species vehicle skills: [moving] {
	point target;
	float leaving_proba <- 0.05;
	float speed;
	float emission <- 0.0;
	
	reflex leave when: (target = nil) and (flip(leaving_proba)) {
		target <- any_location_in(one_of(building));
	}
	
	reflex move when: target != nil {
		if (location = target) {
			target <- nil;
		} else {
			try {
				path path_followed <- goto(target: target, on: road_network, recompute_path: false, return_path: true);
				
				// Pollution logic
				if (path_followed != nil and path_followed.shape != nil) {
					// Update the grid cell at the current location
					ask cell(path_followed.shape.location) {
						grid_value <- grid_value + myself.emission;
					}
				}
			} catch {
				// If pathfinding fails or returns invalid geometry
				target <- nil;
			}
			
			if (location = target) {
				target <- nil;
			} 
		}
	}
}

species car parent: vehicle {
	init {
		emission <- emission_car;
	}
	aspect default {
		draw box(2, 4, 2) color: #crimson rotate: heading;
	}
}

species motorbike parent: vehicle {
	init {
		emission <- emission_bike;
	}
	aspect default {
		draw box(1, 2, 1.5) color: #purple rotate: heading;
	}
}

species bus parent: vehicle {
	init {
		emission <- emission_bus;
	}
	aspect default {
		draw box(3, 8, 3.5) color: #cyan rotate: heading;
	}
}

species ev_vehicle parent: vehicle {
	init {
		emission <- emission_ev;
	}
	aspect default {
		draw box(2, 4, 2) color: #lime rotate: heading;
	}
}

species truck {
	aspect default {
		draw box(3, 6, 3) color: #blue;
	}
}

grid cell width: 300 height: 300 neighbors: 8 {
	float grid_value <- 0.0;
}

// --- EXPERIMENTS ---

experiment "Base Scenario" type: gui {
	parameter "Motorbike Ban In Effect" var: motorbike_ban category: "Policy";
	parameter "Metro System Active" var: metro_active category: "Infrastructure";
	parameter "Subway Capacity" var: subway_capacity category: "Infrastructure";

	output {
		display "Traffic & Pollution" type: 3d background: #lightskyblue axes: false {
			species nature refresh:false;
			species road refresh:false;
			species tree refresh:false;
			species building refresh:false;
			
			species car;
			species motorbike;
			species bus;
			species ev_vehicle;
			species truck;
			
			mesh cell scale: 9 triangulation: true transparency: 0.4 smooth: 3 above: 0.8 color: pal;
		}
		
		display "Charts" {
			chart "Pollution Levels" type: series {
				data "Total Pollution" value: total_pollution color: #red;
			}
		}
	}
}

experiment "Scenario: Motorbike Ban" type: gui {
	parameter "Motorbike Ban In Effect" var: motorbike_ban <- true category: "Policy";
	parameter "Metro System Active" var: metro_active category: "Infrastructure";
	parameter "Subway Capacity" var: subway_capacity category: "Infrastructure";
	
	output {
		display "Traffic & Pollution" type: 3d background: #lightskyblue {
			species nature refresh:false;
			species road refresh:false;
			species building refresh:false;
			species car;
			species motorbike;
			species bus;
			species ev_vehicle;
			mesh cell scale: 9 triangulation: true transparency: 0.4 smooth: 3 above: 0.8 color: pal;
		}
		display "Charts" {
			chart "Pollution Levels" type: series {
				data "Total Pollution" value: total_pollution color: #red;
			}
		}
	}
}

experiment "Scenario: High Capacity Metro" type: gui {
	parameter "Metro System Active" var: metro_active <- true;
	parameter "Subway Capacity" var: subway_capacity <- 0.9;
	
	output {
		display "Traffic & Pollution" type: 3d background: #lightskyblue {
			species nature refresh:false;
			species road refresh:false;
			species building refresh:false;
			species car;
			species motorbike;
			species bus;
			species ev_vehicle;
			mesh cell scale: 9 triangulation: true transparency: 0.4 smooth: 3 above: 0.8 color: pal;
		}
		display "Charts" {
			chart "Pollution Levels" type: series {
				data "Total Pollution" value: total_pollution color: #red;
			}
		}
	}
}