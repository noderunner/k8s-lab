provider "libvirt" {
    uri = "qemu:///session"
}

resource "libvirt_domain" "bip" {
    name = "bip"
}