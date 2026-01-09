/**
* Name: Group4
* Author: ADMIN
* Tags: osm, map, visualization, 3d, google_maps
*/
model Group4

global {
	// --- GLOBAL PARAMETERS ---
	float step <- 1.0 #s;
	field cell <- field(300, 300);
	list<rgb> pal <- palette([#black, #green, #yellow, #orange, #orange, #red, #red, #red]);

	// Scenarios: 0 = Capacity/Ratios, 1 = Signals & Compliance, 2 = Mixed/Chaos
	int scenario_type <- 0;
	float compliance_rate <- 0.5; // Global compliance rate for Scenario 1
	
	int total_throughput <- 0;
	int current_throughput <- 0;
	
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
					
					// Requirement: Split all roads into 2 lanes (or more)
					if (type in ["primary", "trunk", "motorway"]) {
						color <- #orange;
						width <- 12.0;
						num_lanes <- 2; 
					} else {
						color <- #white;
						width <- 8.0;
						num_lanes <- 2;
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
			int nb_cars <- 60;
			int nb_motorbikes <- 100;
			int nb_buses <- 5;
			
			if (scenario_type = 0) {
				// Scenario 1 in more.txt: Predefined traffic ratios
				nb_cars <- 30;
				nb_motorbikes <- 150;
			} else if (scenario_type = 2) {
				// Scenario 3 in more.txt: Chaos / Mixed
				nb_cars <- 80;
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
				location <- any_location_in(one_of(road)); 
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
		diffuse var: cell on: cell proportion: 0.8;
	}
	
	reflex update_throughput when: (cycle mod 100 = 0) {
		current_throughput <- 0;
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
	aspect default { 
		draw shape color: color width: width at: {location.x, location.y, 0.1}; 
		// Visual lane splitting - divider line (solid thin line as linetype is not supported)
		draw shape color: #gray width: 0.2 at: {location.x, location.y, 0.11};
	}
}

species traffic_light {
	bool is_green <- flip(0.5);
	int counter <- rnd(20, 50);
	
	reflex cycle when: (scenario_type = 1) { 
		counter <- counter - 1;
		if (counter <= 0) {
			is_green <- !is_green;
			counter <- rnd(30, 60);
		}
	}
	
	aspect default {
		if (scenario_type = 1) {
			draw sphere(3) color: (is_green ? #green : #red) at: {location.x, location.y, 5};
			draw cylinder(0.5, 5) color: #black at: {location.x, location.y, 0};
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
	float individual_compliance <- 1.0; 
	float lane_offset <- 0.0;
	
	init {
		individual_compliance <- compliance_rate;
		if (scenario_type = 2) {
			lane_offset <- rnd(-3.0, 3.0);
		}
	}

	reflex define_target when: target = nil {
		target <- any_location_in(one_of(building));
	}

	action check_traffic_lights {
		if (scenario_type != 1) { return; } 
		
		traffic_light close_light <- traffic_light closest_to self;
		if (close_light != nil and (location distance_to close_light < 15.0)) {
			if (!close_light.is_green) {
				if (flip(individual_compliance)) {
					speed <- 0.0; 
				} else {
					speed <- max_speed * 0.4; // Violation slow down
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
			list<vehicle> nearby <- vehicle at_distance 3.0;
			if (!empty(nearby)) {
				speed <- speed * 0.8;
			}
			
			path path_followed <- goto(target: target, on: road_network, speed: speed, return_path: true);
			if (path_followed != nil and path_followed.shape != nil) {
				cell[path_followed.shape.location] <- cell[path_followed.shape.location] + 2;					
			}
		}
		
		if (target != nil and location distance_to target < 5.0) {
			target <- nil;
			total_throughput <- total_throughput + 1;
			current_throughput <- current_throughput + 1;
		}
	}
}

species car parent: vehicle {
	init { 
		max_speed <- rnd(30.0, 50.0) #km/#h; 
		speed <- max_speed;
		if (scenario_type != 2) { lane_offset <- 2.5; }
	}
	aspect default { 
		point pos <- location + {lane_offset * cos(heading - 90), lane_offset * sin(heading - 90), 1.0};
		draw box(2, 4, 2) color: #crimson rotate: heading at: pos; 
	}
}

species motorbike parent: vehicle {
	init { 
		max_speed <- rnd(40.0, 60.0) #km/#h; 
		speed <- max_speed;
		if (scenario_type != 2) { lane_offset <- -2.5; }
	}
	aspect default { 
		point pos <- location + {lane_offset * cos(heading - 90), lane_offset * sin(heading - 90), 0.5};
		draw box(1, 2, 1) color: #purple rotate: heading at: pos; 
	}
}

species bus parent: vehicle {
	init { 
		max_speed <- rnd(20.0, 40.0) #km/#h; 
		speed <- max_speed;
		lane_offset <- 0.0;
	}
	aspect default { 
		point pos <- location + {0, 0, 1.5};
		draw box(3, 8, 3) color: #cyan rotate: heading at: pos; 
	}
}

species truck parent: vehicle { 
	init { 
		max_speed <- rnd(30.0, 50.0) #km/#h; 
		speed <- max_speed;
	}
	aspect default { 
		point pos <- location + {0, 0, 1.5};
		draw box(3, 6, 3) color: #blue rotate: heading at: pos; 
	}
}


// --- EXPERIMENT ---

experiment Group4 type: gui {
	parameter "Scenario (0:Ratio, 1:Signal, 2:Chaos)" var: scenario_type min: 0 max: 2;
	parameter "Compliance Rate (Scen 1: 0.2, 0.4, 0.6, 0.8)" var: compliance_rate min: 0.0 max: 1.0 step: 0.1;
	
	output {
		display "Traffic Simulation" type: 3d background: #lightskyblue axes: false {
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
			
			mesh cell scale: 5 triangulation: true transparency: 0.5 smooth: 2 above: 0.5 color: pal;
		}
		
		display "Throughput Analysis" type: 2d {
			chart "Throughput over Time" type: series {
				data "Total Trips" value: total_throughput color: #green;
				data "Recent Trips (per 100 steps)" value: current_throughput color: #blue;
			}
		}
		
		display "Agent Distribution" type: 2d {
			chart "Active Agents" type: pie {
				data "Cars" value: length(car) color: #crimson;
				data "Bikes" value: length(motorbike) color: #purple;
				data "Buses" value: length(bus) color: #cyan;
			}
		}
	}
}
