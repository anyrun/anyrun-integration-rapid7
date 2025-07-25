<p align="center">
    <a href="#readme">
        <img alt="ANY.RUN logo" src="https://raw.githubusercontent.com/anyrun/anyrun-sdk/b3dfde1d3aa018d0a1c3b5d0fa8aaa652e80d883/static/logo.svg">
    </a>
</p>

______________________________________________________________________

# ANY.RUN Threat Intelligence Feed Connector for Rapid7 InsightIDR

Connector delivers fresh, high-confidence IOCs directly from ANY.RUN’s interactive malware sandbox into InsightIDR Community Threats, empowering faster detection and response.

#  Installation Guide

#### Clone this project
```console
$ git clone git@github.com:anyrun/anyrun-integration-rapid7.git
```

#### Jump into the project directory
```console
$ cd anyrun-integration-rapid7/anyrun-integration-insightidr-ti-feed
```

#### Create and fill the .env config. See "Setup secrets" and "Generate Basic Authentication token" sections below
```console
$ cp .env_example .env
```

#### Run the script using two of the following ways:
```console
$ docker-compose up --build
```
```console
$ python3 -m venv venv
$ source venv/bin/scripts/activate
$ pip install -r requirements.txt
$ python3 connector-anyrun-feed.py
```

#  Setup secrets

#### Follow InsightIDR product

![img.png](static/img.png)

#### Select Settings/API Keys
![img_1.png](static/img_1.png)

#### Generate a new API-Key
![img_2.png](static/img_2.png)

#### Use API-KEY as the value for the environment variable: RAPID7_API_KEY

#### Then follow Detection Rules/Community Threads
![img_3.png](static/img_3.png)

#### Create a new custom ThreatFeed with a temporary IOC
![img_4.png](static/img_4.png)

#### Select "View"
![img_5.png](static/img_5.png)

#### Then scroll down and configure the ThreatFeed API-Key with necessary permissions
![img_6.png](static/img_6.png)

#### Use API-KEY as the value for the environment variable: THREAT_FEED_ACCESS_KEY

## Generate Basic Authentication token

To obtain your Basic Authentication token, please contact your ANY.RUN account manager directly or fill out the request [form](https://any.run/demo/?utm_source=opencti_marketplace&utm_medium=integration&utm_campaign=opencti_form).

Use Basic Authentication token, as the value for the environment variable: ANYRUN_BASIC_TOKEN

## Support
This is an ANY.RUN supported connector. For support please contact <anyrun-integrations@any.run>