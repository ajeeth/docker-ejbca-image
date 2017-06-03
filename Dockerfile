#
# Dockerfile for EJBCA server container
#
FROM dataknightllc/alpine:stable
MAINTAINER DataKnight Solutions Development Team <devteam@dataknight.co>

ARG MARIADB_JAVA_CLIENT_VERSION=2.0.1
ARG EJBCA_CE_VERSION=6.5.0.5
ARG EJBCA_CE_FILE_URI=ejbca6/ejbca_6_5_0/ejbca_ce_6_5.0.5.zip
ARG EJBCA_CE_FOLDER=ejbca_ce_6_5.0.5
ARG WILDFLY_VERSION=10.1.0.Final

# Install packages 
RUN set -xe \
    && apk update \
    && apk upgrade \
    && addgroup -S -g 8080 wildfly \
    && adduser -h /opt/wildfly -g '' -s /sbin/nologin -S -H -G wildfly -u 8080 wildfly \
    && mkdir -p /opt/wildfly \
    && apk add --update openjdk8 apache-ant mariadb mariadb-client \
    && curl -L \
        https://sourceforge.net/projects/ejbca/files/${EJBCA_CE_FILE_URI} -o ejbca-${EJBCA_CE_VERSION}.zip \
    && unzip -d /opt ejbca-${EJBCA_CE_VERSION}.zip \
    && rm -f ejbca-${EJBCA_CE_VERSION}.zip \
    && mv /opt/${EJBCA_CE_FOLDER} /opt/ejbca \
    && curl -L \
        https://download.jboss.org/wildfly/${WILDFLY_VERSION}/wildfly-${WILDFLY_VERSION}.tar.gz \
        -o wildfly-${WILDFLY_VERSION}.tar.gz \
    && tar -zxvf "wildfly-${WILDFLY_VERSION}.tar.gz" -C /opt/wildfly --strip-components=1 \
    && rm -f wildfly-${WILDFLY_VERSION}.tar.gz \
    && curl -L \
        https://downloads.mariadb.com/Connectors/java/connector-java-${MARIADB_JAVA_CLIENT_VERSION}/mariadb-java-client-${MARIADB_JAVA_CLIENT_VERSION}.jar \
        -o /opt/wildfly/standalone/deployments/mariadb-java-client.jar \
    && chown -hR wildfly:wildfly /opt/wildfly /opt/ejbca \
    && chmod 750 /opt/wildfly /opt/ejbca \
    && rm -rf /var/cache/apk/* /tmp/* /var/tmp/* /usr/local/src/*

# Configure packages
RUN set -xe \
    && echo JAVA_OPTS="\"\$JAVA_OPTS -Xms2048m -Xmx2048m -Djava.net.preferIPv4Stack=true\"" | \
        tee -a /opt/wildfly/bin/standalone.conf \
    && cd /opt/ejbca \
    && echo database.name=mysql | tee conf/database.properties \
    && echo database.url=jdbc:mysql://127.0.0.1:3306/ejbca?characterEncoding=UTF-8 | tee -a conf/database.properties \
    && echo appserver.home=/opt/wildfly |tee conf/ejbca.properties \
    && chown wildfly:wildfly conf/*.properties \
    && su-exec wildfly ant clean build

# Add files to image
ADD files /

# Configure image
RUN set -xe \
    && chmod a+x /*.sh \
    && mkdir -p /etc/init.d/services-enabled \
    && ln -sf ../services-available/syslog-ng /etc/init.d/services-enabled/syslog-ng \
    && mv /opt/ejbca/conf /opt/ejbca/conf.dist \
    && ln -sf /var/lib/ejbca/conf /opt/ejbca/conf \
    && ln -sf /var/lib/ejbca/p12 /opt/ejbca/p12 \
    && ln -sf /var/lib/ejbca/wildfly/keystore /opt/wildfly/standalone/configuration/keystore

# Configure environment variables
ENV IMAGE_NAME ejbca

# Expose ports
EXPOSE 8080 8442 8443

# Expose volumes
VOLUME /var/lib/mysql /var/lib/ejbca

# Configure default command
CMD [ "ejbca" ]
