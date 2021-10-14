# shift-on-stack-machineset

This Ansible project generates a MachineSet Kubernetes object that can be used
to provision OpenShift worker nodes running on top of OpenStack.  

## Prerequisites

1. Ansible 2.9+
2. Provide a valid **OpenStack** *clouds.yaml* file in the searchpath
3. The **openstack.ansible.cloud** module:

   ```bash
      ansible-galaxy collection install openstack.cloud
   ```

## Configuration

An *inventory.yaml* file provides user-definable parameters related to generating a MachineSet and associated *systemd* service.
