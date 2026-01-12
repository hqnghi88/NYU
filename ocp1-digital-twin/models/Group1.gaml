/**
* Name: OCPMap2
* Author: ADMIN
* Tags: osm, map, visualization, 3d, google_maps
*/
model OCPMap2

global {
// 1. SCENARIOS & PARAMETERS
// Scenario selection
	string scenario <- "baseline" among: ["baseline", "bus_priority"];
	float step <- 1.0 #s;

	// Metrics
	float global_avg_speed <- 0.0;
	float global_pollution <- 0.0;

	// Field for pollution
	field cell <- field(300, 300);
	list<rgb> pal <- palette([#black, #green, #yellow, #orange, #orange, #red, #red, #red]);

	// 2. FILES
	file map_osm_file <- osm_file("../includes/g1.osm");
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
				is_primary <- true;
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
			//						is_primary <- true;
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

			// --- C. NATURE & TREES ---
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

		// --- TRAFFIC ---
		road_network <- as_edge_graph(road);

		// Spawn Vehicles
		if (!empty(road)) {
		// Motorbikes (High volume)
			create motorbike number: 100 {
				location <- any_location_in(one_of(road));
				target <- any_location_in(one_of(building));
			}
			// Cars (Medium volume)
			create car number: 40 {
				location <- any_location_in(one_of(road));
				target <- any_location_in(one_of(building));
			}
			// Buses (Low volume)
			create bus number: 10 {
				location <- any_location_in(one_of(road));
				target <- any_location_in(one_of(building));
			}

		}

		// --- SPAWN TRUCK(S) IN S2 BUILDINGS ---
		list<building> s2_buildings <- building where (each.is_S2);
		if (length(s2_buildings) > 0) {
			create truck number: 5 {
				location <- any_location_in(one_of(s2_buildings).shape);
			}

			write "Truck(s) spawned inside S2 building area.";
		}

	}

	reflex update_global_state {
	// Metrics
		list<vehicle> moving_vehicles <- vehicle where (each.real_speed > 0);
		if (!empty(moving_vehicles)) {
			global_avg_speed <- mean(moving_vehicles collect each.real_speed) * 3.6; // km/h
		} else {
			global_avg_speed <- 0.0;
		}

		global_pollution <- sum(cell);

		// Pollution Decay
		cell <- cell * 0.9;
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
	bool is_primary <- false;

	aspect default {
	// Visual feedback for scenario: Primary roads turn Reddish in Bus Priority mode
		rgb display_color <- color;
		if (scenario = "bus_priority" and is_primary) {
			display_color <- #indianred;
		}

		draw shape color: display_color width: width at: {location.x, location.y, 0.1};
	}

}

species building {
	float height;
	bool is_S2 <- false;

	aspect default {
		draw shape color: (is_S2 ? #gold : #whitesmoke) border: #lightgray depth: height;
	}

}

species vehicle skills: [moving] {
	point target;
	float max_speed;
	float real_speed;
	float emission_rate;
	float size;
	rgb base_color;
	rgb display_color;

	reflex move when: target != nil {
		float speed_modifier <- 1.0;
		float pollution_multiplier <- 1.0;
		display_color <- base_color;

		// Determine current road type
		road current_road <- road(road_network.edges closest_to self);
		if (scenario = "bus_priority") {
			if (current_road != nil and current_road.is_primary) {
				if (self is bus) {
				// Buses get a dedicated lane: FASTER
					speed_modifier <- 1.5;
				} else {
				// Others lose a lane: GRIDLOCK
					speed_modifier <- 0.1; // 10% speed
					pollution_multiplier <- 5.0; // Idling engines pollute more
					display_color <- #darkgray; // Visual cue for "stuck"
				}

			} else {
			// Secondary roads have slight spillover congestion
				speed_modifier <- rnd(0.6, 0.9);
			}

		} else {
		// BASELINE: Random traffic fluctuations
			speed_modifier <- rnd(0.8, 1.0);
		}

		real_speed <- max_speed * speed_modifier;
		do goto target: target on: road_network speed: real_speed;

		// Pollution Emission: Higher if moving slowly/idling
		cell[location] <- cell[location] + (emission_rate * pollution_multiplier);
		if (location = target) {
			target <- any_location_in(one_of(building));
		}

	}

}

species motorbike parent: vehicle {

	init {
		max_speed <- rnd(30.0, 50.0) #km / #h;
		emission_rate <- 2.0;
		size <- 1.0;
		base_color <- #purple;
		display_color <- base_color;
	}

	aspect default {
		draw box(0.5, 1.5, 1) color: display_color rotate: heading;
	}

}

species car parent: vehicle {

	init {
		max_speed <- rnd(40.0, 70.0) #km / #h;
		emission_rate <- 5.0;
		size <- 2.0;
		base_color <- #crimson;
		display_color <- base_color;
	}

	aspect default {
		draw box(2, 4, 2) color: display_color rotate: heading;
	}

}

species bus parent: vehicle {

	init {
		max_speed <- rnd(30.0, 50.0) #km / #h;
		emission_rate <- 10.0;
		size <- 4.0;
		base_color <- #blue;
		display_color <- base_color;
	}

	aspect default {
		draw box(3, 8, 3) color: display_color rotate: heading;
	}

}

species truck {

	aspect default {
		draw box(3, 6, 3) color: #blue;
	}

}

experiment OCPMap2 type: gui {
	parameter "Scenario" var: scenario;
	output {
		display "Google Maps 3D" type: 3d background: #lightskyblue axes: false {
			species nature refresh: false;
			species road; // Enable refresh to see color change
			species tree refresh: false;
			species building refresh: false;
			species motorbike;
			species car;
			species bus;
			species truck;
			mesh cell scale: 1 triangulation: true transparency: 0.4 smooth: 3 above: 0.8 color: pal;
		}

		display "Metrics" type: 2d {
			chart "Average Speed (km/h)" type: series size: {1.0, 0.5} position: {0, 0} {
				data "Speed" value: global_avg_speed color: #blue;
			}

			chart "Total Pollution" type: series size: {1.0, 0.5} position: {0, 0.5} {
				data "Pollution" value: global_pollution color: #red;
			}

		}

	}

}
