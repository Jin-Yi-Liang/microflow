# CMake generated Testfile for 
# Source directory: /home/michael/Micro_flow_PI4
# Build directory: /home/michael/Micro_flow_PI4/build-opt1
# 
# This file includes the relevant testing commands required for 
# testing this directory and lists subdirectories to be tested as well.
add_test(tensor "/home/michael/Micro_flow_PI4/build-opt1/test_tensor")
set_tests_properties(tensor PROPERTIES  _BACKTRACE_TRIPLES "/home/michael/Micro_flow_PI4/CMakeLists.txt;114;add_test;/home/michael/Micro_flow_PI4/CMakeLists.txt;0;")
add_test(image "/home/michael/Micro_flow_PI4/build-opt1/test_image")
set_tests_properties(image PROPERTIES  _BACKTRACE_TRIPLES "/home/michael/Micro_flow_PI4/CMakeLists.txt;115;add_test;/home/michael/Micro_flow_PI4/CMakeLists.txt;0;")
add_test(operators "/home/michael/Micro_flow_PI4/build-opt1/test_operators")
set_tests_properties(operators PROPERTIES  _BACKTRACE_TRIPLES "/home/michael/Micro_flow_PI4/CMakeLists.txt;116;add_test;/home/michael/Micro_flow_PI4/CMakeLists.txt;0;")
add_test(mnist_smoke "/home/michael/Micro_flow_PI4/build-opt1/mnist_demo" "/home/michael/Micro_flow_PI4/models/mnist_improved.mflow" "/home/michael/Micro_flow_PI4/image/test_input.bin")
set_tests_properties(mnist_smoke PROPERTIES  PASS_REGULAR_EXPRESSION "Predicted Digit: \\[7\\]" _BACKTRACE_TRIPLES "/home/michael/Micro_flow_PI4/CMakeLists.txt;117;add_test;/home/michael/Micro_flow_PI4/CMakeLists.txt;0;")
