/**
* Name: Group4
* Author: ADMIN
* Tags: osm, map, visualization, 3d, google_maps
*/
model Group4

import "Traffic.gaml"

global {
//	float seed <- 42.0;
	float traffic_light_interval init: 60 #s;
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
	file map_osm_file <- osm_file("../includes/g4.osm");
	geometry shape <- envelope(map_osm_file);
	graph road_network;
	list<traffic_light> non_deadend_nodes;

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
		list<point> nodes <- [];
		create road from: clean_lines {
			map<string, unknown> atts <- shape.attributes;
			type <- string(atts["highway"]);
			oneway <- string(atts["oneway"]);

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

			nodes <+ first(shape.points);
			nodes <+ last(shape.points);
		}

		// Remove duplicate nodes to ensure correct graph connectivity
		nodes <- remove_duplicates(nodes);

		// Create bidirectional roads for those that are not one-way
		list<road> two_way_roads <- road where (each.oneway != "yes" and each.oneway != "1" and each.oneway != "-1");
		ask two_way_roads {
			create road {
				shape <- polyline(reverse(myself.shape.points));
				type <- myself.type;
				color <- myself.color;
				width <- myself.width;
				num_lanes <- myself.num_lanes;
			}
		}

		create traffic_light from: nodes {
			time_to_change <- traffic_light_interval;
		}

		map edge_weights <- road as_map (each::each.shape.perimeter);
		road_network <- as_driving_graph(road, traffic_light) with_weights edge_weights;
		non_deadend_nodes <- traffic_light where !empty(each.roads_out);
		ask traffic_light {
			if (length(roads_in) > 2) {
				is_traffic_signal <- true;
			}

			do initialize;
		}

		write "Step 3: Building the City...";
		ask osm_agent {
			map<string, unknown> atts <- shape.attributes;
 

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

species building {
	float height;
	bool is_S2 <- false;

	aspect default {
		draw shape color: (is_S2 ? #gold : #whitesmoke) border: #lightgray depth: height;
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
	float speed <- rnd(2.0, 5.0) #km / #h;

	reflex move {
		if (target = nil) {
			target <- any_location_in(one_of(building));
		}

		do goto target: target on: road_network speed: speed;
		if (location distance_to target < 2.0) {
			target <- nil;
		}

	}

	aspect default {
		draw cylinder(0.5, 1.8) color: #pink;
	}

}

species vehicle parent: base_vehicle {

	init {
		road_graph <- road_network;
		location <- one_of(non_deadend_nodes).location;
		right_side_driving <- true;
	}

	// Override to use dynamic road width and lane index
	point compute_position {
		if (current_road != nil) {
			float road_width <- road(current_road).width;
			int n_lanes <- road(current_road).num_lanes;
			// Calculate shift from center. 
			// Lane 0 is rightmost. Vector (heading + 90) points Left.
			// We want Lane 0 to shift Right (negative multiplier).
			
			float lane_w <- road_width / n_lanes;
			float dist_from_left_edge <- (n_lanes - lowest_lane - 0.5) * lane_w;
			float center_offset <- dist_from_left_edge - (road_width / 2);
			
			// Invert sign because +90 deg is Left
			float final_dist <- -center_offset;

			point shift_pt <- {cos(heading + 90) * final_dist, sin(heading + 90) * final_dist};
			return location + shift_pt;
		} else {
			return location;
		}
	}

	// Move the vehicle to a random node when it reaches a deadend
	action relocate {
		do unregister;
		location <- one_of(non_deadend_nodes).location;
		total_throughput <- total_throughput + 1;
		current_throughput <- current_throughput + 1;
	}

	reflex commute {
		// Check if we are at a dead end or finished a path with no next road
		if (next_road = nil and distance_to_current_target <= 0.0) {
			traffic_light current_intersection <- traffic_light closest_to location;
			if (current_intersection = nil or empty(road_network out_edges_of current_intersection)) {
				do relocate;
			} else {
				do drive_random graph: road_graph;
			}
		} else {
			do drive_random graph: road_graph;
		}

	}

}

species car parent: vehicle {

	init {
		max_speed <- rnd(30.0, 50.0) #km / #h;
		speed <- max_speed;
	}

	aspect default {
		point pos <- compute_position();
		// Adjust Z height
		pos <- {pos.x, pos.y, 1.0};
		draw box(4, 2, 2) color: #crimson rotate: heading at: pos;
	}

}

species motorbike parent: vehicle {

	init {
		max_speed <- rnd(40.0, 60.0) #km / #h;
		speed <- max_speed;
	}

	aspect default {
		point pos <- compute_position();
		pos <- {pos.x, pos.y, 0.5};
		draw box(2, 1, 1) color: #purple rotate: heading at: pos;
	}

}

species bus parent: vehicle {

	init {
		max_speed <- rnd(20.0, 40.0) #km / #h;
		speed <- max_speed;
	}

	aspect default {
		point pos <- compute_position();
		pos <- {pos.x, pos.y, 1.5};
		draw box(8, 3, 3) color: #cyan rotate: heading at: pos;
	}

}

species truck parent: vehicle {

	init {
		max_speed <- rnd(30.0, 50.0) #km / #h;
		speed <- max_speed;
	}

	aspect default {
		point pos <- compute_position();
		pos <- {pos.x, pos.y, 1.5};
		draw box(6, 3, 3) color: #blue rotate: heading at: pos;
	}

}

// --- EXPERIMENT ---
experiment Group4 type: gui {
	parameter "Scenario (0:Ratio, 1:Signal, 2:Chaos)" var: scenario_type min: 0 max: 2;
	parameter "Compliance Rate (Scen 1: 0.2, 0.4, 0.6, 0.8)" var: compliance_rate min: 0.0 max: 1.0 step: 0.1;
	output {
		display "Traffic Simulation" type: 3d background: #lightskyblue axes: false {
			species nature refresh: false;
			species road refresh: false;
			species tree refresh: false;
			species building refresh: false;
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
