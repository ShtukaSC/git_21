output "vm_local_ip" {
  value = { for k, v in  yandex_compute_instance.virtual_machine : k => v.network_interface.0.ip_address }
}

output "vm_public_ip" {
  value = { for k, v in  yandex_compute_instance.virtual_machine : k => v.network_interface.0.nat_ip_address}
}

output "vm_info" {
  value = { for k, v in  yandex_compute_instance.virtual_machine : k => "${v.fqdn} ${v.name} ${v.network_interface.0.ip_address}"}
}

output "nlb_ip_address" {
  value = [for s in yandex_lb_network_load_balancer.nlb.listener: s.external_address_spec].0
}
