#!/bin/sh

chmod 755 /usr/bin/load.sh

if [ ! -f /opt/fusion/setup_complete ]; then
    # Setup key
    rm -f /etc/ssh/ssh_host_dsa_key /etc/ssh/ssh_host_rsa_key /root/.ssh/id_rsa
    ssh-keygen -q -N "" -t dsa -f /etc/ssh/ssh_host_dsa_key
    ssh-keygen -q -N "" -t rsa -f /etc/ssh/ssh_host_rsa_key
    ssh-keygen -q -N "" -t rsa -f /root/.ssh/id_rsa
    cp /root/.ssh/id_rsa.pub /root/.ssh/authorized_keys
    chmod 700 /root/.ssh/
    chmod 600 /root/.ssh/authorized_keys
    chmod 700 /root/.ssh/id_rsa
fi

service ssh start

sudo -H -u hadoop /usr/local/hadoop/sbin/start-dfs.sh
sudo -H -u hadoop /usr/local/hadoop/sbin/start-yarn.sh

if [ ! -f /opt/fusion/setup_complete ]; then
    curl -O https://s3.amazonaws.com/wandisco-public-files/fusion/license.key

    touch /opt/fusion/setup_complete

    echo induction.remote.node=$AWS_FUSION_HOST >> /opt/fusion/silent_installer.properties
    cat /opt/fusion/silent_installer.properties
    /opt/wandisco/fusion-ui-server/scripts/silent_installer_full_install.sh /opt/fusion/silent_installer.properties

    cat $HADOOP_PREFIX/etc/hadoop/core-site.xml

    # Restart Hadoop ecosystem.
    sudo -H -u hadoop /usr/local/hadoop/sbin/stop-dfs.sh && /usr/local/hadoop/sbin/stop-yarn.sh
    sudo -H -u hadoop /usr/local/hadoop/sbin/start-dfs.sh && /usr/local/hadoop/sbin/start-yarn.sh

    # create user for hive and hadoop
    useradd -ms /bin/bash -g hadoop sample
    echo 'sample:sample' | chpasswd
    service ssh start
    sudo -H -u hadoop $HADOOP_PREFIX/bin/hdfs namenode -format
    sudo -H -u hadoop /usr/local/hadoop/sbin/start-dfs.sh
    sudo -H -u hadoop /usr/local/hadoop/sbin/start-yarn.sh
    sudo -H -u hadoop /usr/local/hadoop/bin/hadoop fs -mkdir -p /user/sample
    sudo -H -u hadoop /usr/local/hadoop/bin/hadoop fs -mkdir /tmp
    sudo -H -u hadoop /usr/local/hadoop/bin/hadoop fs -mkdir -p /user/hive
    sudo -H -u hadoop /usr/local/hadoop/bin/hadoop fs -mkdir /user/hive/warehouse
    sudo -H -u hadoop /usr/local/hadoop/bin/hadoop fs -chmod g+w /tmp
    sudo -H -u hadoop /usr/local/hadoop/bin/hadoop fs -chmod g+w /user/hive/warehouse
    chmod g+w /opt/hadoop/data
    sudo -H -u hadoop /usr/local/hive/bin/schematool -dbType derby -initSchema

fi

/etc/init.d/fusion-server start
/etc/init.d/fusion-ui-server start
/etc/init.d/fusion-ihc-server-asf_2_7_0 start

# sudo -H -u hadoop /usr/local/hive/bin/hiveserver2 --hiveconf hive.root.logger=DEBUG,console

#tail -f /var/log/fusion/server/fusion-server.log