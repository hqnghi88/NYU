/**
* Name: OCPMap2
* Author: ADMIN
* Tags: osm, map, visualization, 3d, google_maps
*/
model OCPMap2

global {
// 1. SMOOTH TIME
	float step <- 0.1 #s;
	field cell <- field(300, 300);
	list<rgb> pal <- palette([#black, #green, #yellow, #orange, #orange, #red, #red, #red]);

	// --- SCENARIOS (From more.txt) ---
	// "Baseline": Current Hanoi situation (80% motos, gas cars, few electrics)
	// "Green Future": Expanded bus network, introduced rental scooters, more electric vehicles
	string scenario_type <- "Baseline" among: ["Baseline", "Green Future"];

	// Global Statistics
	float mean_pollution -> mean(cell);
	int total_vehicles -> length(vehicle);

	// 2. FILES
	file map_osm_file <- osm_file("../includes/g5.osm");
	geometry shape <- envelope(map_osm_file);
	graph road_network;

	init {
		write "Step 1: Reading file...";
		list<geometry> osm_shapes <- map_osm_file.contents;
		write "Step 2: Processing Agents...";
		// Manual loop to prevent crash
		loop geom over: osm_shapes {
			create osm_agent {
				shape <- geom;
			}

		}

		list<geometry> rr <- [];
		ask osm_agent {
			map<string, unknown> atts <- shape.attributes;

			// --- A. ROADS ---
			if (atts contains_key "highway") {
				rr <+ shape;
			}

		}

		list<geometry> clean_lines <- clean_network(rr, 3.0, true, true);
		create road from: clean_lines {
			map<string, unknown> atts <- shape.attributes;
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

		write "Step 3: Building the City...";
		ask osm_agent {
			map<string, unknown> atts <- shape.attributes;

			// --- A. ROADS ---
			//			if (atts contains_key "highway") {
			//				create road {
			//					shape <- myself.shape;
			//					type <- string(atts["highway"]);
			//					if (type in ["primary", "trunk", "motorway"]) {
			//						color <- #orange;
			//						width <- 10.0;
			//					} else if (type in ["secondary", "tertiary"]) {
			//						color <- #white;
			//						width <- 7.0;
			//					} else {
			//						color <- #white;
			//						width <- 4.0;
			//					}
			//				}
			//			}

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

					// Detect S2 buildings inside the OSM file
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
			// Destroy the temp agent
			do die;
		}

		// --- TRAFFIC NETWORK ---
		road_network <- as_edge_graph(road);

		// --- BUS STOPS ---
		// Expand bus stop density in Green Future scenario
		float stop_density_prob <- (scenario_type = "Baseline") ? 0.002 : 0.01;
		ask road {
		// Place stops on long enough road segments
			if (length(shape) > 40 and flip(stop_density_prob)) {
				create bus_stop {
					location <- any_location_in(myself.shape);
				}

			}

		}

		if (empty(bus_stop)) {
		// Fallback if no random stops created
			create bus_stop number: 5 {
				location <- any_location_in(one_of(road));
			}

		}

		// --- SPAWN VEHICLES BASED ON SCENARIO ---
		// Total vehicle count for simulation
		int sim_capacity <- 200;

		// Distribution Ratios
		float r_moto <- 0.0;
		float r_gas_car <- 0.0;
		float r_ecar <- 0.0;
		float r_bus <- 0.0;
		float r_scooter <- 0.0;
		if (scenario_type = "Baseline") {
		// Observations: ~80% gas motorcycles, 10% gas cars, 5% VinFast (e-car), 5% others/bus
			r_moto <- 0.8;
			r_gas_car <- 0.1;
			r_ecar <- 0.05;
			r_bus <- 0.05;
			r_scooter <- 0.0;
		} else {
		// Future: Less motos, more public transport (bus), rental scooters for short trips
			r_moto <- 0.40;
			r_gas_car <- 0.10;
			r_ecar <- 0.20; // Increased e-car adoption
			r_bus <- 0.15; // Expanded bus network
			r_scooter <- 0.15; // Rental scooters
		}

		create moto number: int(sim_capacity * r_moto) {
			location <- any_location_in(one_of(road));
		}

		create gas_car number: int(sim_capacity * r_gas_car) {
			location <- any_location_in(one_of(road));
		}

		create electric_car number: int(sim_capacity * r_ecar) {
			location <- any_location_in(one_of(road));
		}

		create bus number: int(sim_capacity * r_bus) {
			location <- any_location_in(one_of(road));
		}

		create scooter number: int(sim_capacity * r_scooter) {
			location <- any_location_in(one_of(road));
		}

		// --- SPAWN TRUCK(S) IN S2 BUILDINGS (Existing Logic) ---
		list<building> s2_buildings <- building where (each.is_S2);
		if (length(s2_buildings) > 0) {
			create truck number: 5 {
				location <- any_location_in(one_of(s2_buildings).shape);
			}

			write "Truck(s) spawned inside S2 building area.";
		}

	}

	//Reflex to decrease and diffuse the pollution of the environment
	reflex pollution_evolution {
	//ask all cells to decrease their level of pollution
		cell <- cell * 0.95; // Dissipation

		//diffuse the pollutions to neighbor cells
		diffuse var: pollution on: cell proportion: 0.8;
	}

}

// --- SPECIES ---
species osm_agent {
}

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

species bus_stop {

	aspect default {
		draw circle(5) color: #yellow border: #black;
		draw "BUS" color: #black size: 4 at: location + {0, 0, 2};
	}

}

species building {
	float height;
	bool is_S2 <- false;

	aspect default {
		draw shape color: (is_S2 ? #gold : #whitesmoke) border: #lightgray depth: height;
	}

}

// --- TRAFFIC SPECIES ---
species vehicle skills: [moving] {
	point target;
	float pollution_emission <- 0.0;
	float speed <- 30.0 #km / #h;
	rgb color <- #gray;
	geometry shape_geom;

	reflex move when: target != nil {
		if (location distance_to target < 5.0) {
			target <- nil;
		} else {
			path path_followed <- goto(target: target, on: road_network, recompute_path: false, return_path: true);

			// Pollution logic
			if (path_followed != nil and path_followed.shape != nil) {
				cell[path_followed.shape.location] <- cell[path_followed.shape.location] + pollution_emission;
			} } }

			// Abstract target picking
	reflex pick_target when: target = nil {
		do find_target;
	}

	action find_target {
		target <- any_location_in(one_of(road));
	}

	aspect default {
		if (shape_geom != nil) {
			draw shape_geom color: color rotate: heading at: location + {0, 0, 1};
		} else {
			draw box(2, 4, 2) color: color rotate: heading;
		}

	} }

species moto parent: vehicle {

	init {
		pollution_emission <- 10.0; // High pollution for gas motos
		speed <- rnd(30.0, 60.0) #km / #h;
		color <- #brown;
		shape_geom <- box(1, 2, 1.5);
	}

	// Motos go anywhere (buildings/roads)
	action find_target {
		if (flip(0.5)) {
			target <- any_location_in(one_of(building));
		} else {
			target <- any_location_in(one_of(road));
		}

	}

}

species gas_car parent: vehicle {

	init {
		pollution_emission <- 15.0; // Higher pollution
		speed <- rnd(30.0, 70.0) #km / #h;
		color <- #crimson;
		shape_geom <- box(2, 4, 2);
	}

	action find_target {
		target <- any_location_in(one_of(building));
	}

}

species electric_car parent: vehicle {

	init {
		pollution_emission <- 0.0; // Clean
		speed <- rnd(30.0, 70.0) #km / #h;
		color <- #cyan;
		shape_geom <- box(2, 4, 2);
	}

	action find_target {
		target <- any_location_in(one_of(building));
	}

}

species bus parent: vehicle {

	init {
		pollution_emission <- 2.0; // Low pollution (efficient/electric mix)
		speed <- rnd(20.0, 50.0) #km / #h;
		color <- #blue;
		shape_geom <- box(3, 8, 3);
	}

	// Buses move between bus stops
	action find_target {
		if (!empty(bus_stop)) {
			target <- one_of(bus_stop).location;
		} else {
			target <- any_location_in(one_of(road));
		}

	}

}

species scooter parent: vehicle {

	init {
		pollution_emission <- 0.0; // Clean
		speed <- rnd(15.0, 30.0) #km / #h;
		color <- #lime;
		shape_geom <- cylinder(0.5, 1.5);
	}

	// Scooters take short trips
	action find_target {
	// Try to find a building within 500m
		building local_dest <- one_of(building where (each distance_to self < 500.0));
		if (local_dest != nil) {
			target <- any_location_in(local_dest);
		} else {
			target <- any_location_in(one_of(road));
		}

	}

}

species truck parent: vehicle {

	init {
		pollution_emission <- 20.0;
		speed <- 40 #km / #h;
		color <- #darkblue;
		shape_geom <- box(3, 7, 3.5);
	}

}

experiment OCPMap2 type: gui {
// Allow user to select scenario
	parameter "Scenario" var: scenario_type;
	output {
		layout #split;
		display "Google Maps 3D" type: 3d background: #lightskyblue axes: false {
			species nature refresh: false;
			species road refresh: false;
			species tree refresh: false;
			species building refresh: false;
			species bus_stop refresh: false;
			species moto;
			species gas_car;
			species electric_car;
			species bus;
			species scooter;
			species truck;
			mesh cell scale: 9 triangulation: true transparency: 0.4 smooth: 3 above: 0.8 color: pal;
		}

		display "Statistics" type: java2D {
			chart "Air Pollution Level" type: series size: {1.0, 0.5} position: {0, 0} {
				data "Mean Pollution" value: mean_pollution color: #red;
			}

			chart "Vehicle Composition" type: pie size: {1.0, 0.5} position: {0, 0.5} {
				data "Motos" value: length(moto) color: #brown;
				data "Gas Cars" value: length(gas_car) color: #crimson;
				data "E-Cars" value: length(electric_car) color: #cyan;
				data "Buses" value: length(bus) color: #blue;
				data "Scooters" value: length(scooter) color: #lime;
			}

		}

	}

}