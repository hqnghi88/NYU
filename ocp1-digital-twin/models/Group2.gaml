/**
* Name: OCPMap2
* Author: ADMIN
* Tags: osm, map, visualization, 3d, google_maps
*/
model OCPMap2

global {
// --- SCENARIO PARAMETERS ---
	bool scenario_buses <- false;
	bool scenario_block_hospital_streets <- false;
	bool scenario_stagger_school <- false;
	int nb_buses <- 5;

	// --- 1. CORE ENVIRONMENT ---
	float step <- 1.0 #s; // Adjusted for better traffic flow simulation
	field cell <- field(300, 300);
	list<rgb> pal <- palette([#black, #green, #yellow, #orange, #orange, #red, #red, #red]);

	// --- 2. FILES ---
	file map_osm_file <- osm_file("../includes/g2.osm");
	geometry shape <- envelope(map_osm_file);
	graph road_network;

	// --- 3. GLOBAL LISTS ---
	list<building> schools;
	list<building> hospitals;
	list<building> s2_buildings;

	// --- METRICS ---
	float average_pollution -> {mean(cell)};
	float hospital_pollution -> {empty(hospitals) ? 0.0 : mean(hospitals collect (cell[each.location]))};
	float average_speed -> {mean(car collect each.real_speed)};

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

					// Height
					if (atts contains_key "building:levels") {
						height <- float(atts["building:levels"]) * 3.5;
					} else {
						height <- rnd(8.0, 20.0);
					}

					// Identification
					if (atts contains_key "amenity") {
						string amenity <- string(atts["amenity"]);
						if (amenity = "school" or amenity = "university") {
							type <- "school";
							color <- #cyan;
						} else if (amenity = "hospital" or amenity = "clinic") {
							type <- "hospital";
							color <- #magenta;
						}

					}

					// Detect S2 buildings
					if (atts contains_key "name" and ("S2" in string(atts["name"]))) {
						is_S2 <- true;
						color <- #gold;
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

		// --- SETUP GROUPS ---
		schools <- building where (each.type = "school");
		hospitals <- building where (each.type = "hospital");
		s2_buildings <- building where (each.is_S2);

		// Fallback if no specific buildings found (for robust simulation)
		if (empty(schools)) {
			write "No schools found in OSM. Randomly assigning 2.";
			ask 2 among building {
				type <- "school";
				color <- #cyan;
			}

			schools <- building where (each.type = "school");
		}

		if (empty(hospitals)) {
			write "No hospitals found in OSM. Randomly assigning 1.";
			ask 1 among building {
				type <- "hospital";
				color <- #magenta;
			}

			hospitals <- building where (each.type = "hospital");
		}

		// --- SCENARIO: BLOCK STREETS ---
		if (scenario_block_hospital_streets) {
			write "Blocking streets near hospitals...";
			geometry restricted_zone <- union(hospitals collect (each.shape + 150.0));
			ask road overlapping restricted_zone {
				do die;
			}

		}

		// --- TRAFFIC NETWORK ---
		road_network <- as_edge_graph(road);

		// --- SCENARIO: BUSES ---
		if (scenario_buses) {
			write "Initializing Bus System...";
			// Create stops near hospitals and random locations to form a route
			list<point> stop_locations;
			ask hospitals {
				stop_locations <+ any_location_in(shape);
			}

			ask 3 among building {
				stop_locations <+ any_location_in(shape);
			}

			loop loc over: stop_locations {
				create bus_stop {
					location <- loc;
				}

			}

			create bus number: nb_buses {
				location <- one_of(bus_stop).location;
				stops <- list(bus_stop); // All buses serve all stops for simplicity
			}

		}

		// --- CARS (General Traffic + School Traffic) ---
		if (!empty(road)) {
			create car number: 60 {
				location <- any_location_in(one_of(road));
				speed <- rnd(30.0, 70.0) #km / #h;
				// Some cars are school runs
				if (flip(0.3)) { // 30% are school related
					is_school_run <- true;
					target_building <- one_of(schools);
				}

			}

		}

		// --- TRUCKS (S2) ---
		if (!empty(s2_buildings)) {
			create truck number: 5 {
				location <- any_location_in(one_of(s2_buildings).shape);
			}

		}

	}

	reflex pollution_evolution {
	// Diffuse pollution
		diffuse var: pollution on: cell proportion: 0.8;
		// Decay
		cell <- cell * 0.99;
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

species building {
	float height;
	bool is_S2 <- false;
	string type <- "residential"; // residential, school, hospital
	aspect default {
		draw shape color: color border: #lightgray depth: height;
	}

}

species bus_stop {

	aspect default {
		draw circle(5) color: #yellow border: #black;
		draw "BUS" color: #black size: 4 at: location + {0, 0, 5};
	}

}

species bus skills: [moving] {
	float speed <- 40 #km / #h;
	list<bus_stop> stops;
	int current_stop_index <- 0;

	reflex move {
		if (empty(stops)) {
			return;
		}

		bus_stop target_stop <- stops[current_stop_index];
		do goto target: target_stop on: road_network;
		if (location = target_stop.location) {
			current_stop_index <- (current_stop_index + 1) mod length(stops);
		}

	}

	// Buses reduce pollution slightly by taking people? Or emit less per person?
	// For now, let's say they emit pollution too.
	reflex pollute {
		cell[location] <- cell[location] + 5;
	}

	aspect default {
		draw box(4, 10, 4) color: #yellow rotate: heading;
	}

}

species car skills: [moving] {
	point target;
	building target_building;
	bool is_school_run <- false;
	float leaving_proba <- 0.05;
	float speed <- rnd(30.0, 70.0) #km / #h;

	reflex decide_target when: target = nil {
		if (is_school_run) {
		// SCENARIO: STAGGER SCHOOL
		// If staggered, we wait for specific time windows or spread out probability
			if (scenario_stagger_school) {
			// High chance to move only occasionally to simulate staggered flow
				if (flip(0.02)) {
					target <- any_location_in(target_building);
				}

			} else {
			// Everyone rushes (higher prob)
				if (flip(0.1)) {
					target <- any_location_in(target_building);
				}

			}

		} else {
		// Normal random traffic
			if (flip(leaving_proba)) {
				target <- any_location_in(one_of(building));
			}

		}

	}

	reflex move when: target != nil {
		path path_followed <- goto(target: target, on: road_network, recompute_path: false, return_path: true);
		if (path_followed != nil and path_followed.shape != nil) {
			cell[path_followed.shape.location] <- cell[path_followed.shape.location] + 10;
		}

		if (location = target) {
			target <- nil;
			if (is_school_run) {
			// Once at school, maybe go home later? For now, reset to random building
				is_school_run <- false;
			}

		} }

	aspect default {
		draw box(2, 4, 2) color: (is_school_run ? #cyan : #crimson) rotate: heading;
	} }

species truck skills: [moving] {
// Simple random movement for now to add to traffic
	point target;

	reflex move {
		if (target = nil) {
			target <- any_location_in(one_of(building));
		}

		do goto target: target on: road_network;
		if (location = target) {
			target <- nil;
		}

		cell[location] <- cell[location] + 20; // Trucks pollute more
	}

	aspect default {
		draw box(3, 6, 3) color: #blue rotate: heading;
	}

}

experiment OCPMap2 type: gui {
// Expose parameters to UI
	parameter "Enable Bus System" var: scenario_buses category: "Scenarios";
	parameter "Block Streets near Hospital" var: scenario_block_hospital_streets category: "Scenarios";
	parameter "Stagger School Class Times" var: scenario_stagger_school category: "Scenarios";
	parameter "Number of Buses" var: nb_buses category: "Scenarios" min: 0 max: 20;
	output {
		layout #split;
		display "Digital Twin 3D" type: 3d background: #lightskyblue axes: false {
			species nature refresh: false;
			species road refresh: false;
			species tree refresh: false;
			species building refresh: false;
			species bus_stop;
			species car;
			species bus;
			species truck;
			mesh cell scale: 9 triangulation: true transparency: 0.4 smooth: 3 above: 0.8 color: pal;
		}

		display "Analytics" {
			chart "Pollution Levels" type: series size: {1.0, 0.5} position: {0, 0} {
				data "Global Average" value: average_pollution color: #gray;
				data "Hospital Vicinity" value: hospital_pollution color: #red;
			}

			chart "Traffic Metrics" type: series size: {1.0, 0.5} position: {0, 0.5} {
				data "Avg Speed (km/h)" value: average_speed color: #blue;
			}

		}

	}

}