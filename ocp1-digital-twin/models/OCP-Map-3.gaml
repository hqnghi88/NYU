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

	// 2. FILES
	file map_osm_file <- osm_file("../includes/map.osm");
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

		write "Step 3: Building the City...";
		ask osm_agent {
			map<string, unknown> atts <- shape.attributes;

			// --- A. ROADS ---
			// FIX: Use simple 'if', not 'else if' to avoid type mismatch errors
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

			//			// --- B. BUILDINGS ---
			//			if (atts contains_key "building") {
			//				create building {
			//					shape <- myself.shape;
			//					if (atts contains_key "building:levels") {
			//						height <- float(atts["building:levels"]) * 3.5; 
			//					} else {
			//						height <- rnd(8.0, 20.0); 
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

		// --- TRAFFIC ---
		road_network <- as_edge_graph(road);
		if (!empty(road)) {
			create car number: 60 {
				location <- any_location_in(one_of(road));
				speed <- rnd(30.0, 70.0) #km / #h;
			}

		}

		// --- SPAWN TRUCK(S) IN S2 BUILDINGS ---
		list<building> s2_buildings <- building where (each.is_S2);
		if (length(s2_buildings) > 0) {
			create truck number: 5 {
				location <- any_location_in(one_of(s2_buildings).shape);
			}

			write "Truck(s) spawned inside S2 building area.";
		} else {
			write "No S2 buildings found!";
		}

	}


	//Reflex to decrease and diffuse the pollution of the environment
	reflex pollution_evolution {
		//ask all cells to decrease their level of pollution
//		cell <- cell * 0.8;
	
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

//species building {
//	float height;
//	aspect default { 
//		draw shape color: #whitesmoke border: #lightgray depth: height;
//	}
//}
species building {
	float height;
	bool is_S2 <- false;

	aspect default {
		draw shape color: (is_S2 ? #gold : #whitesmoke) border: #lightgray depth: height;
	}

}

species car skills: [moving] {

//Target point of the agent
	point target;
	//Probability of leaving the building
	float leaving_proba <- 0.05;
	//Speed of the agent
	float speed <- rnd(10) #km / #h + 1;
	// Random state
	string state;
	//Reflex to leave the building to another building
	reflex leave when: (target = nil) and (flip(leaving_proba)) {
		target <- any_location_in(one_of(building));
	}
	//Reflex to move to the target building moving on the road network
	reflex move when: target != nil {
	//we use the return_path facet to return the path followed
		path path_followed <- goto(target: target, on: road_network, recompute_path: false, return_path: true);

		//if the path followed is not nil (i.e. the agent moved this step), we use it to increase the pollution level of overlapping cell
		if (path_followed != nil and path_followed.shape != nil) {
			cell[path_followed.shape.location] <- cell[path_followed.shape.location] + 10;					
		}

		if (location = target) {
			target <- nil;
		} }

	aspect default {
		draw box(2, 4, 2) color: #crimson rotate: heading;
	}

}

// create truck species
species truck {

	aspect default {
		draw box(3, 6, 3) color: #blue;
	}

}

experiment OCPMap2 type: gui {
	output {
		display "Google Maps 3D" type: 3d background: #lightskyblue axes: false {
			species nature refresh:false;
			species road refresh:false;
			species tree refresh:false;
			species building refresh:false;
			species car;
			species truck;
			mesh cell scale: 9 triangulation: true transparency: 0.4 smooth: 3 above: 0.8 color: pal;
		}

	}

}


