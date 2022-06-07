#!/bin/bash

echo -e "Setting up Local Machine for Administration\n"

main()
{
    03-client-tools
    04-generate-and-distribute-certs
    05-client-authentication-config
}

03-client-tools()
{
    ssh-keygen -q -t rsa -N '' <<< $'\ny' >/dev/null 2>&1
    cat ~/.ssh/id_rsa.pub >> ~/.ssh/authorized_keys

    wget https://storage.googleapis.com/kubernetes-release/release/v1.13.0/bin/linux/amd64/kubectl

    chmod +x kubectl
    sudo mv kubectl /usr/local/bin/

    kubectl version --client
}

04-generate-and-distribute-certs()
{
    certificate-authority
    client-server-admin-cert
    kubelet-cert
    kube-apiserver-cert
    ETCD-cert
    distribute-certs
}

certificate-authority()
{
    ## Certificate Authority

    # Create private key for CA
    openssl genrsa -out ca.key 2048

    # Comment line starting with RANDFILE in /etc/ssl/openssl.cnf definition to avoid permission issues
    sudo sed -i '0,/RANDFILE/{s/RANDFILE/\#&/}' /etc/ssl/openssl.cnf

    # Create CSR using the private key
    openssl req -new -key ca.key -subj "/CN=KUBERNETES-CA" -out ca.csr

    # Self sign the csr using its own private key
    openssl x509 -req -in ca.csr -signkey ca.key -CAcreateserial  -out ca.crt -days 1000
}

client-server-admin-cert()
{

    ## Client & Server  Admin Certs

    # Generate private key for admin user
    openssl genrsa -out admin.key 2048

    # Generate CSR for admin user. Note the OU.
    openssl req -new -key admin.key -subj "/CN=admin/O=system:masters" -out admin.csr

    # Sign certificate for admin user using CA servers private key
    openssl x509 -req -in admin.csr -CA ca.crt -CAkey ca.key -CAcreateserial  -out admin.crt -days 1000
}

kubelet-cert()    
{    
    ## The Kubelet Client Certificates

    # Generate the kube-controller-manager client certificate and private key:

    openssl genrsa -out kube-controller-manager.key 2048
    openssl req -new -key kube-controller-manager.key -subj "/CN=system:kube-controller-manager" -out kube-controller-manager.csr
    openssl x509 -req -in kube-controller-manager.csr -CA ca.crt -CAkey ca.key -CAcreateserial -out kube-controller-manager.crt -days 1000


    ## Generate the kube-proxy client certificate and private key:

    openssl genrsa -out kube-proxy.key 2048
    openssl req -new -key kube-proxy.key -subj "/CN=system:kube-proxy" -out kube-proxy.csr
    openssl x509 -req -in kube-proxy.csr -CA ca.crt -CAkey ca.key -CAcreateserial  -out kube-proxy.crt -days 1000

    ## Generate the kube-scheduler client certificate and private key:

    openssl genrsa -out kube-scheduler.key 2048
    openssl req -new -key kube-scheduler.key -subj "/CN=system:kube-scheduler" -out kube-scheduler.csr
    openssl x509 -req -in kube-scheduler.csr -CA ca.crt -CAkey ca.key -CAcreateserial  -out kube-scheduler.crt -days 1000
}


kube-apiserver-cert()
{
    ## The Kubernetes API Server Certificate
    openssl-config
    # Generates certs for kube-apiserver

    openssl genrsa -out kube-apiserver.key 2048
    openssl req -new -key kube-apiserver.key -subj "/CN=kube-apiserver" -out kube-apiserver.csr -config openssl.cnf
    openssl x509 -req -in kube-apiserver.csr -CA ca.crt -CAkey ca.key -CAcreateserial  -out kube-apiserver.crt -extensions v3_req -extfile openssl.cnf -days 1000
}

ETCD-cert()
{
    # The ETCD Server Certificate
    openssl-etcd-config 
    # Generates certs for ETCD

    openssl genrsa -out etcd-server.key 2048
    openssl req -new -key etcd-server.key -subj "/CN=etcd-server" -out etcd-server.csr -config openssl-etcd.cnf
    openssl x509 -req -in etcd-server.csr -CA ca.crt -CAkey ca.key -CAcreateserial  -out etcd-server.crt -extensions v3_req -extfile openssl-etcd.cnf -days 1000

    ## The Service Account Key Pair

    openssl genrsa -out service-account.key 2048
    openssl req -new -key service-account.key -subj "/CN=service-accounts" -out service-account.csr
    openssl x509 -req -in service-account.csr -CA ca.crt -CAkey ca.key -CAcreateserial  -out service-account.crt -days 1000

}

distribute-certs()
{
    # Distribute the Certificates
    # Copy the appropriate certificates and private keys to each controller instance:

    for instance in master-1 master-2; do
        HOST=${instance}
        PORT=$(vagrant ssh-config $HOST | grep Port | grep -o '[0-9]\+')        
        pwd
        scp -P $PORT -i ./.vagrant/machines/$HOST/virtualbox/private_key \
            ca.crt ca.key \
            kube-apiserver.key kube-apiserver.crt \
            service-account.key service-account.crt \
            etcd-server.key etcd-server.crt \
            vagrant@localhost:~/     
    done
}

05-client-authentication-config()
{
    LOADBALANCER_ADDRESS=192.168.5.30
    admin-kube-config
    kube-proxy-config
    kube-controller-manager-config
    kube-scheduler-config
    distribute-kube-configs
}
admin-kube-config()
{
     kubectl config set-cluster kubernetes-the-hard-way \
    --certificate-authority=ca.crt \
    --embed-certs=true \
    --server=https://127.0.0.1:6443 \
    --kubeconfig=admin.kubeconfig

    kubectl config set-credentials admin \
    --client-certificate=admin.crt \
    --client-key=admin.key \
    --embed-certs=true \
    --kubeconfig=admin.kubeconfig

    kubectl config set-context default \
    --cluster=kubernetes-the-hard-way \
    --user=admin \
    --kubeconfig=admin.kubeconfig

    kubectl config use-context default --kubeconfig=admin.kubeconfig
}
kube-proxy-config()
{
   
    kubectl config set-cluster kubernetes-the-hard-way \
    --certificate-authority=ca.crt \
    --embed-certs=true \
    --server=https://${LOADBALANCER_ADDRESS}:6443 \
    --kubeconfig=kube-proxy.kubeconfig

    kubectl config set-credentials system:kube-proxy \
    --client-certificate=kube-proxy.crt \
    --client-key=kube-proxy.key \
    --embed-certs=true \
    --kubeconfig=kube-proxy.kubeconfig

    kubectl config set-context default \
    --cluster=kubernetes-the-hard-way \
    --user=system:kube-proxy \
    --kubeconfig=kube-proxy.kubeconfig

    kubectl config use-context default --kubeconfig=kube-proxy.kubeconfig

}
kube-controller-manager-config()
{
     kubectl config set-cluster kubernetes-the-hard-way \
    --certificate-authority=ca.crt \
    --embed-certs=true \
    --server=https://127.0.0.1:6443 \
    --kubeconfig=kube-controller-manager.kubeconfig

    kubectl config set-credentials system:kube-controller-manager \
    --client-certificate=kube-controller-manager.crt \
    --client-key=kube-controller-manager.key \
    --embed-certs=true \
    --kubeconfig=kube-controller-manager.kubeconfig

    kubectl config set-context default \
    --cluster=kubernetes-the-hard-way \
    --user=system:kube-controller-manager \
    --kubeconfig=kube-controller-manager.kubeconfig

    kubectl config use-context default --kubeconfig=kube-controller-manager.kubeconfig
}
kube-scheduler-config()
{
     kubectl config set-cluster kubernetes-the-hard-way \
    --certificate-authority=ca.crt \
    --embed-certs=true \
    --server=https://127.0.0.1:6443 \
    --kubeconfig=kube-scheduler.kubeconfig

    kubectl config set-credentials system:kube-scheduler \
    --client-certificate=kube-scheduler.crt \
    --client-key=kube-scheduler.key \
    --embed-certs=true \
    --kubeconfig=kube-scheduler.kubeconfig

    kubectl config set-context default \
    --cluster=kubernetes-the-hard-way \
    --user=system:kube-scheduler \
    --kubeconfig=kube-scheduler.kubeconfig

    kubectl config use-context default --kubeconfig=kube-scheduler.kubeconfig
}
distribute-kube-configs()
{
    for instance in worker-1 worker-2; do        
        HOST=${instance}
        PORT=$(vagrant ssh-config $HOST | grep Port | grep -o '[0-9]\+')        
        scp -P $PORT -i ./.vagrant/machines/$HOST/virtualbox/private_key \
            admin.kubeconfig kube-proxy.kubeconfig vagrant@localhost:~/
    done

    for instance in master-1 master-2; do
        HOST=${instance}
        PORT=$(vagrant ssh-config $HOST | grep Port | grep -o '[0-9]\+')
        scp -P $PORT -i ./.vagrant/machines/$HOST/virtualbox/private_key \
            admin.kubeconfig \
            kube-controller-manager.kubeconfig \
            kube-scheduler.kubeconfig \
            vagrant@localhost:~/        
    done
}
openssl-config()
{
cat >openssl.cnf<<-EOF

[req]
req_extensions = v3_req
distinguished_name = req_distinguished_name
[req_distinguished_name]
[ v3_req ]
basicConstraints = CA:FALSE
keyUsage = nonRepudiation, digitalSignature, keyEncipherment
subjectAltName = @alt_names
[alt_names]
DNS.1 = kubernetes
DNS.2 = kubernetes.default
DNS.3 = kubernetes.default.svc
DNS.4 = kubernetes.default.svc.cluster.local
IP.1 = 10.96.0.1
IP.2 = 192.168.5.11
IP.3 = 192.168.5.12
IP.4 = 192.168.5.30
IP.5 = 127.0.0.1

EOF
}
openssl-etcd-config()
{
cat >openssl-etcd.cnf<<-EOF

[req]
req_extensions = v3_req
distinguished_name = req_distinguished_name
[req_distinguished_name]
[ v3_req ]
basicConstraints = CA:FALSE
keyUsage = nonRepudiation, digitalSignature, keyEncipherment
subjectAltName = @alt_names
[alt_names]
IP.1 = 192.168.5.11
IP.2 = 192.168.5.12
IP.3 = 127.0.0.1

EOF
}
main