#!/bin/bash

echo "Setting up ETCD Distributed Cluster\n"

main()
{
    06-data-encryption-setup
    07-bootstrap-etcd
}
06-data-encryption-setup()
{
    ENCRYPTION_KEY=$(head -c 32 /dev/urandom | base64)
    encryption-config
    distribute-encryption-config-to-masters
}

encryption-config()
{
cat > encryption-config.yaml <<EOF
kind: EncryptionConfig
apiVersion: v1
resources:
  - resources:
      - secrets
    providers:
      - aescbc:
          keys:
            - name: key1
              secret: ${ENCRYPTION_KEY}
      - identity: {}
EOF
}
distribute-encryption-config-to-masters()
{
    # Copy the encryption-config.yaml encryption config file to each controller instance:

    for instance in master-1 master-2; do        
        HOST=${instance}
        PORT=$(vagrant ssh-config $HOST | grep Port | grep -o '[0-9]\+')
        scp -P $PORT -i ./.vagrant/machines/$HOST/virtualbox/private_key \
            encryption-config.yaml  \
            ./ubuntu/setup-master.sh \
            vagrant@localhost:~/ 
    done
}
07-bootstrap-etcd(){
    for instance in master-1 master-2; do        
        HOST=${instance}
        #PORT=$(vagrant ssh-config $HOST | grep Port | grep -o '[0-9]\+')
        ssh $(vagrant ssh-config $HOST | sed '/^[[:space:]]*$/d' |  awk 'NR>1 {print " -o "$1"="$2}') localhost "./setup-master.sh"
    done

    for instance in master-1 master-2; do        
        HOST=${instance}
        #PORT=$(vagrant ssh-config $HOST | grep Port | grep -o '[0-9]\+')
        ssh $(vagrant ssh-config $HOST | sed '/^[[:space:]]*$/d' |  awk 'NR>1 {print " -o "$1"="$2}') localhost <<'EOL'
            sudo ETCDCTL_API=3 etcdctl member list \
            --endpoints=https://127.0.0.1:2379 \
            --cacert=/etc/etcd/ca.crt \
            --cert=/etc/etcd/etcd-server.crt \
            --key=/etc/etcd/etcd-server.key
EOL
    done
}
main