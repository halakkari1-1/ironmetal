#!/bin/bash
# Builds the engine-sim core (MIT, AngeTheGreat) as a static library for Linux, without its Windows UI.
cd /home/claude/esim
E=es-src; S=$E/dependencies/submodules/simple-2d-constraint-solver
mkdir -p obj
CORE="audio_buffer camshaft combustion_chamber connecting_rod convolution_filter crankshaft cylinder_bank cylinder_head delay_filter derivative_filter direct_throttle_linkage dynamometer engine exhaust_system feedback_comb_filter filter fuel function gas_system gaussian_filter governor ignition_module impulse_response intake jitter_filter leveling_filter low_pass_filter part piston piston_engine_simulator simulator standard_valvetrain starter_motor synthesizer throttle transmission utilities valvetrain vehicle vehicle_drag_constraint vtec_valvetrain"
F="-std=c++17 -O2 -fpermissive -Wno-changes-meaning -D__forceinline=inline -include cstring -include cmath -include cstdint -include algorithm -I stub -I $E/include -I $E/dependencies/submodules"
for f in $CORE; do [ obj/$f.o -nt $E/src/$f.cpp ] || g++ $F -c $E/src/$f.cpp -o obj/$f.o 2>&1 | grep -m3 "error" & done; wait
for f in $S/src/*.cpp; do g++ $F -I $S/include -c $f -o obj/scs_$(basename $f .cpp).o 2>&1 | grep -m2 error & done; wait
rm -f libes.a; ar rcs libes.a obj/*.o
