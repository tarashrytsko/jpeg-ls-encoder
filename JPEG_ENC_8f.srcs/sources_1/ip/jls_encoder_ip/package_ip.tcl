# package_ip.tcl — Package jls_encoder as Vivado IP Core
# Run in Vivado TCL console: source package_ip.tcl

set ip_name "jls_encoder_ip"
set ip_version "1.0"
set ip_vendor "user.org"
set ip_library "jpegls"
set ip_dir [file dirname [info script]]

# Create a managed IP project
create_project -force ${ip_name}_pkg ${ip_dir}/pkg_project -part xc7a200tfbg676-2
set_property ip_repo_paths ${ip_dir} [current_project]

# Add source files
add_files -norecurse [list \
    ${ip_dir}/hdl/jls_encoder_ip.v \
    ${ip_dir}/hdl/jls_encoder.v \
]
update_compile_order -fileset sources_1

# Package the IP
ipx::package_project -root_dir ${ip_dir} -vendor ${ip_vendor} -library ${ip_library} \
    -taxonomy /UserIP -import_files -set_current true

# Set IP identification
set_property vendor ${ip_vendor} [ipx::current_core]
set_property library ${ip_library} [ipx::current_core]
set_property name ${ip_name} [ipx::current_core]
set_property version ${ip_version} [ipx::current_core]
set_property display_name "JPEG-LS Encoder Core" [ipx::current_core]
set_property description "Lossless/near-lossless JPEG-LS encoder with AXI-Stream interface" [ipx::current_core]
set_property vendor_display_name "Custom" [ipx::current_core]

# Define AXI-Stream Slave interface (pixel input)
ipx::add_bus_interface S_AXIS [ipx::current_core]
set_property abstraction_type_vlnv xilinx.com:interface:axis_rtl:1.0 [ipx::get_bus_interfaces S_AXIS -of_objects [ipx::current_core]]
set_property bus_type_vlnv xilinx.com:interface:axis:1.0 [ipx::get_bus_interfaces S_AXIS -of_objects [ipx::current_core]]
set_property interface_mode slave [ipx::get_bus_interfaces S_AXIS -of_objects [ipx::current_core]]
ipx::add_port_map TDATA [ipx::get_bus_interfaces S_AXIS -of_objects [ipx::current_core]]
set_property physical_name s_axis_tdata [ipx::get_port_maps TDATA -of_objects [ipx::get_bus_interfaces S_AXIS -of_objects [ipx::current_core]]]
ipx::add_port_map TVALID [ipx::get_bus_interfaces S_AXIS -of_objects [ipx::current_core]]
set_property physical_name s_axis_tvalid [ipx::get_port_maps TVALID -of_objects [ipx::get_bus_interfaces S_AXIS -of_objects [ipx::current_core]]]
ipx::add_port_map TREADY [ipx::get_bus_interfaces S_AXIS -of_objects [ipx::current_core]]
set_property physical_name s_axis_tready [ipx::get_port_maps TREADY -of_objects [ipx::get_bus_interfaces S_AXIS -of_objects [ipx::current_core]]]

# Define AXI-Stream Master interface (compressed output)
ipx::add_bus_interface M_AXIS [ipx::current_core]
set_property abstraction_type_vlnv xilinx.com:interface:axis_rtl:1.0 [ipx::get_bus_interfaces M_AXIS -of_objects [ipx::current_core]]
set_property bus_type_vlnv xilinx.com:interface:axis:1.0 [ipx::get_bus_interfaces M_AXIS -of_objects [ipx::current_core]]
set_property interface_mode master [ipx::get_bus_interfaces M_AXIS -of_objects [ipx::current_core]]
ipx::add_port_map TDATA [ipx::get_bus_interfaces M_AXIS -of_objects [ipx::current_core]]
set_property physical_name m_axis_tdata [ipx::get_port_maps TDATA -of_objects [ipx::get_bus_interfaces M_AXIS -of_objects [ipx::current_core]]]
ipx::add_port_map TVALID [ipx::get_bus_interfaces M_AXIS -of_objects [ipx::current_core]]
set_property physical_name m_axis_tvalid [ipx::get_port_maps TVALID -of_objects [ipx::get_bus_interfaces M_AXIS -of_objects [ipx::current_core]]]
ipx::add_port_map TLAST [ipx::get_bus_interfaces M_AXIS -of_objects [ipx::current_core]]
set_property physical_name m_axis_tlast [ipx::get_port_maps TLAST -of_objects [ipx::get_bus_interfaces M_AXIS -of_objects [ipx::current_core]]]
ipx::add_port_map TREADY [ipx::get_bus_interfaces M_AXIS -of_objects [ipx::current_core]]
set_property physical_name m_axis_tready [ipx::get_port_maps TREADY -of_objects [ipx::get_bus_interfaces M_AXIS -of_objects [ipx::current_core]]]

# Associate clock with interfaces
ipx::associate_bus_interfaces -busif S_AXIS -clock aclk [ipx::current_core]
ipx::associate_bus_interfaces -busif M_AXIS -clock aclk [ipx::current_core]

# Add user parameters
ipx::add_user_parameter NEAR [ipx::current_core]
set_property value_resolve_type user [ipx::get_user_parameters NEAR -of_objects [ipx::current_core]]
set_property value 0 [ipx::get_user_parameters NEAR -of_objects [ipx::current_core]]
set_property value_format long [ipx::get_user_parameters NEAR -of_objects [ipx::current_core]]
set_property value_validation_type range_long [ipx::get_user_parameters NEAR -of_objects [ipx::current_core]]
set_property value_validation_range_minimum 0 [ipx::get_user_parameters NEAR -of_objects [ipx::current_core]]
set_property value_validation_range_maximum 7 [ipx::get_user_parameters NEAR -of_objects [ipx::current_core]]

# Save and package
ipx::create_xgui_files [ipx::current_core]
ipx::update_checksums [ipx::current_core]
ipx::save_core [ipx::current_core]

puts "=== IP Core packaged successfully: ${ip_name} v${ip_version} ==="
puts "Location: ${ip_dir}"
puts "Add to IP Catalog: Settings > IP > Repository > Add ${ip_dir}"

close_project
