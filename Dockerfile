#
# Dockerfile for EJBCA server container
#
FROM dataknightllc/wildfly:stable
MAINTAINER DataKnight Solutions Development Team <devteam@dataknight.co>

ARG MARIADB_JAVA_CLIENT_VERSION=2.0.1
ARG MARIADB_DOWNLOAD_URL=https://downloads.mariadb.com/Connectors/java/connector-java-${MARIADB_JAVA_CLIENT_VERSION}
ARG EJBCA_CE_VERSION=6.5.0.5
ARG EJBCA_CE_FILE_URI=ejbca6/ejbca_6_5_0/ejbca_ce_6_5.0.5.zip
ARG EJBCA_CE_FOLDER=ejbca_ce_6_5.0.5

# Install packages 
RUN set -xe \
  && apk update \
  && apk upgrade \
  && apk add --update apache-ant mariadb-client \
  && curl -L https://sourceforge.net/projects/ejbca/files/${EJBCA_CE_FILE_URI} -o ejbca-${EJBCA_CE_VERSION}.zip \
  && unzip -d /opt ejbca-${EJBCA_CE_VERSION}.zip \
  && rm -f ejbca-${EJBCA_CE_VERSION}.zip \
  && mv /opt/${EJBCA_CE_FOLDER} /opt/ejbca \
  && curl -L ${MARIADB_DOWNLOAD_URL}/mariadb-java-client-${MARIADB_JAVA_CLIENT_VERSION}.jar -o \
    /opt/jboss/wildfly/standalone/deployments/mariadb-java-client.jar \
  && chown -hR root:root /opt/ejbca \
  && rm -rf /var/cache/apk/* /tmp/* /var/tmp/* /usr/local/src/*

# Build EJBCA
RUN set -xe \
  && echo JAVA_OPTS="\"\$JAVA_OPTS -Xms2048m -Xmx2048m -Djava.net.preferIPv4Stack=true\"" | \
    tee -a /opt/jboss/wildfly/bin/standalone.conf \
  && cd /opt/ejbca \
  && echo database.name=mysql | tee conf/database.properties \
  && echo appserver.home=/opt/jboss/wildfly |tee conf/ejbca.properties \
  && ant clean build \
  && cp dist/ejbca.ear /opt/jboss/wildfly/standalone/deployments/ \
  && chmod 0750 /opt/jboss/wildfly/standalone/configuration \
  && mv conf conf.dist \
  && ln -sf /var/lib/ejbca/conf conf \
  && ln -sf /var/lib/ejbca/keystore p12 \
  && ln -sf /var/lib/ejbca/wildfly/standalone.xml /opt/jboss/wildfly/standalone/configuration/standalone.xml \
  && ln -sf /var/lib/ejbca/wildfly/keystore /opt/jboss/wildfly/standalone/configuration/keystore \
  && ln -sf /opt/ejbca/bin/ejbca.sh /usr/local/bin/ejbca \
  && rm -rf tmp

# Add files to image
ADD files /

# Configure image
RUN set -xe \
  && chmod a+x /*.sh \
  && chown -hR wildfly:wildfly /opt/ejbca /opt/jboss/wildfly

# Configure environment variables
ENV IMAGE_NAME ejbca

# Expose ports
EXPOSE 8080 8442 8443

# Configure default command
CMD [ "run" ]
