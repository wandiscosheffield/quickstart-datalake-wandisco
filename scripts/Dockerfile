FROM ubuntu:14.04
MAINTAINER "Akito Nozaki" <akito.nozaki@sturdynetworks.com>

USER root
ENV LANG C.UTF-8

RUN apt-get update

### Setup JAVA
ENV JAVA_HOME /usr/lib/jvm/java-8-openjdk-amd64
ENV PATH $PATH:$JAVA_HOME/bin

RUN apt-get install -y software-properties-common python-software-properties \
 && add-apt-repository ppa:openjdk-r/ppa \
 && apt-get update \
 && apt-get install -y openjdk-8-jdk ca-certificates-java \
 && update-java-alternatives -s java-1.8.0-openjdk-amd64 \
 && update-ca-certificates -f

### Setup SSH w/ passwordless login
RUN apt-get install -y openssh-client openssh-server ssh net-tools

# Setup SSH Config
RUN echo 'PubkeyAuthentication yes' >> /etc/ssh/sshd_config \
 && sed -i 's/PasswordAuthentication yes/PasswordAuthentication no/g' /etc/ssh/sshd_config \
 && echo "AuthorizedKeysFile %h/.ssh/authorized_keys" >> /etc/ssh/sshd_config \
 && echo "PubkeyAuthentication yes" >> /etc/ssh/sshd_config \
 && echo "    IdentityFile ~/.ssh/id_rsa" >> /etc/ssh/ssh_config \
 && echo "    StrictHostKeyChecking no" >> /etc/ssh/ssh_config \
 && echo "    UserKnownHostsFile=/dev/null" >> /etc/ssh/ssh_config \
 && mkdir -p /var/run/sshd \
 && chmod 755 /var/run/sshd

### Install other tools
RUN apt-get install -y build-essential lzop git rsync curl python-dev python-setuptools libcurl4-openssl-dev sudo

RUN easy_install pip \
 && pip install virtualenv virtualenvwrapper python-dateutil

RUN groupadd -r hadoop \
 && useradd -ms /bin/bash -g hadoop hadoop \
 && sudo -H -u hadoop ssh-keygen -q -N "" -t rsa -f /home/hadoop/.ssh/id_rsa \
 && sudo -H -u hadoop cp /home/hadoop/.ssh/id_rsa.pub /home/hadoop/.ssh/authorized_keys \
 && sudo -H -u hadoop chmod 600 /home/hadoop/.ssh/authorized_keys

WORKDIR /tmp

ENV HADOOP_VERSION 2.7.0
RUN curl -O -L "https://www.apache.org/dyn/mirrors/closest.cgi?action=download&filename=hadoop/common/hadoop-${HADOOP_VERSION}/hadoop-${HADOOP_VERSION}.tar.gz" \
 && tar xvzf hadoop-${HADOOP_VERSION}.tar.gz \
 && mv hadoop-${HADOOP_VERSION} /usr/local/ \
 && chown -R hadoop:hadoop /usr/local/hadoop-${HADOOP_VERSION} \
 && chmod g+w -R /usr/local/hadoop-${HADOOP_VERSION} \
 && ln -s /usr/local/hadoop-${HADOOP_VERSION} /usr/local/hadoop \
 && rm hadoop-${HADOOP_VERSION}.tar.gz

ENV HADOOP_PREFIX /usr/local/hadoop
ENV HADOOP_COMMON_HOME /usr/local/hadoop
ENV HADOOP_HDFS_HOME /usr/local/hadoop
ENV HADOOP_MAPRED_HOME /usr/local/hadoop
ENV HADOOP_YARN_HOME /usr/local/hadoop
ENV HADOOP_CONF_DIR /usr/local/hadoop/etc/hadoop
ENV YARN_CONF_DIR $HADOOP_PREFIX/etc/hadoop

ENV HADOOP_HOME $HADOOP_PREFIX

# These configuration is setup for "Pseudo-Distributed Operation" and assumes a single node.
ADD config/core-site.xml.template $HADOOP_PREFIX/etc/hadoop/core-site.xml
ADD config/hdfs-site.xml.template $HADOOP_PREFIX/etc/hadoop/hdfs-site.xml
ADD config/mapred-site.xml.template $HADOOP_PREFIX/etc/hadoop/mapred-site.xml
ADD config/yarn-site.xml.template $HADOOP_PREFIX/etc/hadoop/yarn-site.xml

# create data directory configured in core-site.xml 
RUN mkdir -p /opt/hadoop/data \
 && chown hadoop:hadoop -R /opt/hadoop/data

# Update hadoop environment stuff
RUN sed -i '/^export JAVA_HOME/ s:.*:export JAVA_HOME=/usr/lib/jvm/java-8-openjdk-amd64\nexport HADOOP_PREFIX=/usr/local/hadoop\nexport HADOOP_HOME=/usr/local/hadoop\n:' $HADOOP_PREFIX/etc/hadoop/hadoop-env.sh
RUN sed -i '/^export HADOOP_CONF_DIR/ s:.*:export HADOOP_CONF_DIR=/usr/local/hadoop/etc/hadoop/:' $HADOOP_PREFIX/etc/hadoop/hadoop-env.sh

# Install HIVE
ENV HIVE_VERSION 2.1.1

RUN curl -O -L "https://www.apache.org/dyn/mirrors/closest.cgi?action=download&filename=hive/hive-${HIVE_VERSION}/apache-hive-${HIVE_VERSION}-bin.tar.gz" \
 && tar xvzf apache-hive-${HIVE_VERSION}-bin.tar.gz \
 && mv apache-hive-${HIVE_VERSION}-bin /usr/local/apache-hive-${HIVE_VERSION}-bin \
 && chown -R hadoop:hadoop /usr/local/apache-hive-${HIVE_VERSION}-bin \
 && ln -s /usr/local/apache-hive-${HIVE_VERSION}-bin /usr/local/hive \
 && cp /usr/local/hive/conf/hive-default.xml.template /usr/local/hive/conf/hive-site.xml \
 && sed -i 's/metastore_db/\/opt\/derby\/metastore_db/' /usr/local/hive/conf/hive-site.xml \
 && sed -i 's/${system:java.io.tmpdir}/\/tmp/g' /usr/local/hive/conf/hive-site.xml \
 && sed -i 's/${system:user.name}/hive/g' /usr/local/hive/conf/hive-site.xml \
 && echo "export HADOOP_HOME=/usr/local/hadoop" >> /usr/local/hive/bin/hive-config.sh \
 && mkdir -p /opt/derby/ \
 && chown hadoop:hadoop /opt/derby \
 && rm apache-hive-${HIVE_VERSION}-bin.tar.gz

ENV PATH $PATH:$HADOOP_HOME/bin:$HIVE_HOME/bin

# Add all these to profile so sshing into the box will set the environment properly
RUN echo '' >> /etc/profile \
 && echo '# JDK config' >> /etc/profile \
 && echo "export JAVA_HOME=$JAVA_HOME" >> /etc/profile \
 && echo '' >> /etc/profile \
 && echo '# Hadoop config' >> /etc/profile \
 && echo "export HADOOP_HOME=$HADOOP_HOME" >> /etc/profile \
 && echo '' >> /etc/profile \
 && echo '# Hive config' >> /etc/profile \
 && echo 'export HIVE_HOME=/usr/local/hive' >> /etc/profile \
 && echo '' >> /etc/profile \
 && echo 'export PATH=$PATH' >> /etc/profile


ENV FUSION_CORE_INSTALLER fusion-hcfs-asf-2.7.0-client-hdfs_2.10.3.1-2485_all.deb
COPY $FUSION_CORE_INSTALLER $FUSION_CORE_INSTALLER
RUN dpkg -i $FUSION_CORE_INSTALLER \
 && rm $FUSION_CORE_INSTALLER

COPY silent_install_env.sh /opt/fusion/silent_install_env.sh
ENV SILENT_CONFIG_PATH /opt/fusion/silent_install_env.sh

ENV FUSION_UI_INSTALLER fusion-ui-server-asf_deb_installer.6.sh
COPY $FUSION_UI_INSTALLER /opt/fusion/$FUSION_UI_INSTALLER
RUN chmod 755 /opt/fusion/$FUSION_UI_INSTALLER \
 && /opt/fusion/$FUSION_UI_INSTALLER

COPY silent_installer.properties /opt/fusion/silent_installer.properties

RUN mkdir -p /etc/hadoop \
 && ln -s  $HADOOP_PREFIX/etc/hadoop/ /etc/hadoop/conf

ADD scripts/startup.sh /usr/bin/startup.sh
ADD scripts/load.sh /usr/bin/load.sh
CMD ["/usr/bin/startup.sh"]

# Hdfs ports
EXPOSE 50010 50020 50070 50075 50090 8020 9000
# Mapred ports
EXPOSE 10020 19888
# Yarn ports
EXPOSE 8030 8031 8032 8033 8040 8042 8088
# Hive ports
EXPOSE 10000 10001
# Fusion Server
EXPOSE 8083
