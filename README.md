## EJBCA PKI Server
This is an image for running your own [EJBCA PKI](https://www.ejbca.org) server.

[![build](https://circleci.com/gh/dataknightllc/docker-ejbca-image/tree/master.svg?style=shield&circle-token=f6ca71486c51971be9e2dbb5e07730c792b0aa89)](https://circleci.com/gh/dataknightllc/docker-ejbca-image/tree/master)

### Prerequisites
- Install [Docker Compose](https://github.com/docker/compose) on the system.
- Review the documentation for [EJBCA PKI](https://www.ejbca.org/docs/index.html) for details on how to configure and
  use the product.
- Choose a location on the system in which to store EJBCA PKI configuration settings and data.

### Container Setup
Follow the steps below to set up the container.  These instructions assume you have chosen **/opt/docker/ejbca** as
a base folder for storing settings and data.  If you choose a different path, please update the path in the commands
below accordingly.

1. On the Docker host, create the **docker-compose.yml** file inside the **/opt/docker/ejbca** folder.  The 
   format is shown below in the **Docker Compose Configuration** section.
2. Create the necessary configuration and data folders.
   - `host# mkdir -p /opt/docker/ejbca/{mysql,data}`
3. Pull the latest image from the registry:
   - `host# docker-compose pull ejbca`
4. Review the **Container Initialization** section below on how to pre-configure the container with your own custom
   settings, if desired.
5. Use **docker-compose** to bring up the container:
   - `host# docker-compose up ejbca`

In the future, you can update the container by simply re-running **docker-compose pull ejbca** followed by
**docker-compose up --force-recreate ejbca**.  These commands will automatically pull the latest version of
the image(s) from the registry and replace it without affecting your data or configurations.

### Docker Compose Configuration
Below is a sample `docker-compose.yml` file for your reference:
```
#
# Sample configuration for 'ejbca' container
#

version: "3"

services:
  mariadb:
    container_name: mariadb
    image: dataknightllc/mariadb:stable
    volumes:
      - /opt/docker/mariadb/rsyslog:/etc/rsyslog/conf.d
      - /opt/docker/mariadb/data:/var/lib/mysql
    ports:
      - 3306:3306
    environment:
      TZ: ${TZ:-UTC}
      SECRETS_FOLDER: /run/secrets
  
  ejbca:
    container_name: ejbca
    image: dataknightllc/ejbca:stable
    volumes:
      - /opt/docker/ejbca/syslog-ng:/etc/syslog-ng/conf.d
      - /opt/docker/ejbca/mysql:/var/lib/mysql
      - /opt/docker/ejbca/data:/var/lib/ejbca
    ports:
      - 8080:8080
      - 8442:8442
      - 8443:8443
    environment:
      TZ: ${TZ:-UTC}
```

### Backing Up the Container
Once you have configured the container per the instructions above, you simply need to backup the **/opt/docker/ejbca**
folder and subfolders to save your configuration and data.

### Container Initialization
This container image is configured so that the first time you boot it, it will automatically initialize a new
Certificate Authority and database for you with little to no intervention.  Please be aware that the first boot
of the container may take some time (~5 minutes or so) in order to initialize the MySQL database and Wildfly
server for running EJBCA.

You may notice several folders such as **/var/lib/mysql/.init** and **/var/lib/ejbca/.init** that are created
automatically during first boot.  You should not touch these folders or files.  They are used for keeping
initialization state for your container between reboots and upgrades or container rebuilds.  Likewise, once the
initial boot has been performed, you should not alter the values or settings in the **/var/lib/mysql/.vault** and
**/var/lib/ejbca/.vault** files unless otherwise noted.

If you wish to use the default settings, you do not have to do anything other than set up the container as described
in the steps above.  A default certificate authority called **Root Certificate Authority** will be created and 
initialized for you automatically during first boot.

If you wish to customize settings for the initialization, you may do so by following the instructions below.  Any
files created below should be owned by the **root** user and set to mode 0600.  Settings for _.properties_ files
described below are assigned values each on a single line using _setting=value_ syntax.  If the value of any setting
contains spaces, be sure to wrap it in double quote (") marks.  If you choose to create a file, it **must** contain
all of the settings specified.

**NOTE:** If you choose to supply your own password for any of the settings listed below, it must be a **minimum** of
6 characters long.

__MySQL User Customization__
If you wish to set your own password for the **root** and/or **ejbca** user, simply create a new file corresponding
to the username in the **/var/lib/mysql/.vault** folder.  The file should _only_ contain the password and nothing else.

__Certificate Authority Customization__
If you wish to customize the CA that is created during first boot, create a new file called **ca.properties** inside
the **/var/lib/ejbca/.vault** folder.
  - **ca.name**: The common name of the certificate authority (eg: "My CA")
  - **ca.dn**: The fully distinguished name of the certificate authority (eg: "CN=My CA,O=My Company,C=US") 
  - **ca.keytype**: Should always be **RSA**
  - **ca.keyspec**: The number of bits of encryption to use for the private key (eg: 1024 or 2048 or 4096)
  - **ca.signaturealgorithm**: Use **SHA256WithRSA** unless you know what you're doing
  - **ca.validity**: The number of days until the CA expires (eg: 7300 which is 20 years)
  - **ca.policy**: Use **null** unless you know what you're doing
  - **ca.tokenpassword**: The password used to encrypt the CA private key

__Java Customization__
If you wish to customize Java settings used during first boot, create a new file called **java.properties** inside
the **/var/lib/ejbca/.vault** folder.
  - **java.trustpassword**: The password used to encrypt the Java keystore for storing the SSL certificate for
                            the Wildfly web server.

__SuperAdmin Customization__
If you wish to customize settings used to create the super administrator account during first boot, create a new file
called **superadmin.properties** inside the **/var/lib/ejbca/.vault** folder.
  - **superadmin.cn**: The common name of the super administrator account (eg: admin)
  - **superadmin.dn**: The fully distinguished name of the super administrator account (eg: CN=admin)
  - **superadmin.password**: The password used to encrypt the PKCS12 keystore containing the user's SSL client
                             certificate
  - **superadmin.batch**: Must be set to **true**

__HTTPS Server Customization__
If you wish to customize settings used for the SSL certificate for the Wildfly web server generated during first boot,
create a new file called **httpsserver.properties** inside the **/var/lib/ejbca/.vault** folder.
  - **httpsserver.hostname**: The common name of the web server (eg: pki.mydomain.com)
  - **httpsserver.dn**: The fully distinguished name to use in the SSL certificate (eg: CN=pki.mydomain.com)
  - **httpsserver.password**: The password used to encrypt the private SSL key

__SMTP Server Customization__
If you wish to customize settings used for sending email from EJBCA, create a new file called **smtpserver.properties**
inside the **/var/lib/ejbca/.vault** folder.
  - **smtpserver.enabled**: **true** to enable and use the SMTP settings or **false** to ignore them
  - **smtpserver.port**: SMTP server port (eg: 25 or 587)
  - **smtpserver.host**: Hostname (or FQDN depending on your configuration) of the SMTP server
  - **smtpserver.from**: E-mail address used in the **From:** address
  - **smtpserver.user**: Username for SMTP server authentication or leave blank if not required
  - **smtpserver.password**: Password for SMTP server authentication or leave blank if not required
  - **smtpserver.use_tls**: **true** to use TLS when connecting to the SMTP server or **false** to use cleartext

### Logging into EJBCA as a Super Administrator
Once the server is up and running, you'll want to connect to the Web UI and login as the administrator.

1. Download the **/var/lib/ejbca/p12/superadmin.p12** file from the container to your local system.
2. Grab the value of **superadmin.password** from the **/var/lib/ejbca/.vault/superadmin.properties** file in the
   container.
3. Import the PKCS12 file onto your system (for IE, Edge and Chrome) or into your browser (for Firefox).
4. Restart your browser.
5. Navigate to https://ejbcaserver:8443/ejbca/adminweb where _ejbcaserver_ is the hostname or IP of your 
   EJBCA server.

### Activating the Certificate Authority
After the initial boot of the container, you will need to activate the certificate authority for use.  You'll need to
log into the Web UI and perform the steps that follow.

1. Open your browser and navigate to https://ejbcaserver:8443/ejbca/adminweb where _ejbcaserver_ is the hostname or IP
   of your EJBCA server.
2. Click the **CA Activation** link under **CA Functions**.
3. Under the **Crypto Token Action** check the **Activate** box.
4. Grab the value of **ca.tokenpassword** from the **/var/lib/ejbca/.vault/ca.properties** file in the container and
   enter it next to **Crypto Token activation code**.
5. Click the **Apply** button.

Note that afterwards you may want to turn on auto-activation by clicking on the link for the CA and going into edit
mode and making the change.

### Changing the Certificate Authority Password
...TO BE DOCUMENTED...

### Updating the Wildfly Web Server Certificate
If you wish to update the SSL certificate used by the Wildfly front-end web server because it has expired or if you
wish to change its properties or use a different CA to sign the certificate, you'll need to perform the steps that
follow.

__Using the EJBCA Certificate Authority__
Follow the steps below to generate a new certificate using the EJBCA Certificate Authority you created.

1. Open your browser and navigate to https://ejbcaserver:8443/ejbca/adminweb where _ejbcaserver_ is the hostname or IP
   of your EJBCA server.
2. Click the **Search End Entities** link under **RA Functions**.
3. Next to **Search end entity with username** enter **tomcat** and click **Search**.
4. Click the **Edit End Entity** link in the search result.
5. Change the **Status** from **Generated** to **New**.
6. Grab the value of **httpsserver.password** from the **/var/lib/ejbca/.vault/httpsserver.properties** file in the 
   container and enter it in the **Password (or Enrollment Code)** and **Confirm Password** fields.
7. Finish editing the entity as desired and click **Save** when complete.
8. Run the following command from a shell within the container:
   - `/opt/ejbca/bin/ejbca.sh batch`
   - `keytool -changealias -keystore /var/lib/ejbca/p12/tomcat.jks -alias _CertCN_ -destalias ejbca`
     (Be sure to change _CertCN_ to the actual CN you specified for the certificate!)
   - `cp /var/lib/ejbca/wildfly/keystore/keystore.jks /var/lib/ejbca/wildfly/keystore/keystore.jks.bak`
   - `cp /var/lib/ejbca/p12/tomcat.jks /var/lib/ejbca/wildfly/keystore/keystore.jks`
   - `chown wildfly:wildfly /var/lib/ejbca/wildfly/keystore/keystore.jks*`
   - `/opt/wildfly/bin/jboss-cli.sh -c --command=":shutdown(restart=true)"`

__Using a 3rd Party Certificate Authority__
Follow the steps below to generate a new certificate using a 3rd party CA such as Verisign, Comodo, Thawte, etc.

1. Open a shell on the container and run the following command:  
   `keytool -genkey -alias ejbca -keyalg RSA -keysize 2048 -keystore /tmp/keystore.jks`
2. Grab the value of **httpsserver.password** from the **/var/lib/ejbca/.vault/httpsserver.properties** file in the 
   container and use it when prompted for a password for the keystore.
3. Enter the details for the certificate as you are prompted for them.
4. Press **ENTER** when asked for the password for the **ejbca** key.
5. Now run the following command:
   `keytool -certreq -alias ejbca -keyalg RSA -file /tmp/request.csr -keystore /tmp/keystore.jks`
6. Submit the **/tmp/request.csr** file to the CA for signing.  Be sure to request a certificate for Java/Tomcat/JBOSS
   so that the signed certificate is in PKCS7 (.p7b) format.
7. Upload the signed PKCS7 bundle to the container as **/tmp/cert.p7b**.
8. Now run the following commands:
   - `keytool -import -trustcacerts -alias ejbca -file /tmp/cert.p7b -keystore /tmp/keystore.jks`
   - `cp /var/lib/ejbca/wildfly/keystore/keystore.jks /var/lib/ejbca/wildfly/keystore/keystore.jks.bak`
   - `cp /tmp/keystore.jks /var/lib/ejbca/wildfly/keystore/keystore.jks`
   - `chown wildfly:wildfly /var/lib/ejbca/wildfly/keystore/keystore.jks*`
   - `/opt/wildfly/bin/jboss-cli.sh -c --command=":shutdown(restart=true)"`

__Importing an Existing SSL Key Pair__
...TO BE DOCUMENTED...

If you encounter any issues with Wildfly not restarting, simply copy the **keystore.jks.bak** file back to
**keystore.jks** and issue the restart command to **jboss-cli.sh**.

### Troubleshooting Errors
If you have issues, be sure to check the log files in the **/var/log** folder for details.  The majority of information
will be stored in the **wildfly.log** file.

### Additional Help or Questions
If you have questions, find bugs or need additional help, please send an email to 
[support@dataknight.co](mailto:support@dataknight.co).
