import time
from datetime import datetime, timedelta, UTC
from http import HTTPStatus

import requests

from anyrun import RunTimeException
from anyrun.connectors import FeedsConnector
from anyrun.iterators import FeedsIterator

from utils.config import Config
from utils.logs import FileLoggingManager

DATE_TIME_FORMAT = "%Y-%m-%d %H:%M:%S"
logger = FileLoggingManager()


def main():
    while True:
        logger.info('[ANY.RUN] Enrichment with indicators has begun.')
        replace_indicators()

        logger.info('[ANY.RUN] Enrichment with indicators has successfully completed.')
        time.sleep(Config.ANYRUN_FEED_FETCH_INTERVAL * 60)


def replace_indicators() -> None:
    """
    Initializes IOC enrichment in Rapid7
    """
    url = f'{Config.RAPID7_HOST}/idr/v1/customthreats/key/{Config.THREAT_FEED_ACCESS_KEY}/indicators/replace?format=json'

    payload = {
        "ips": get_indicators('ip'),
        "domain_names": get_indicators('domain'),
        "urls": get_indicators('url')
    }

    make_request(url, payload)


def get_indicators(indicator_type: str) -> list[str | None]:
    """
    Gets actual indicators using ANY.RUN TAXII STIX server

    :param indicator_type: ANY.RUN indicator type
    :return: List of the indicators
    """
    indicators = []

    with FeedsConnector(api_key=Config.ANYRUN_BASIC_TOKEN, integration=Config.RAPID7_API_KEY) as connector:
        for feeds in FeedsIterator.taxii_stix(
            connector,
            collection=indicator_type,
            match_type='indicator',
            match_version='all',
            chunk_size=5000,
            limit=5000,
            modified_after=(datetime.now(UTC) - timedelta(days=Config.ANYRUN_FEED_FETCH_DEPTH)).strftime(DATE_TIME_FORMAT)
        ):

            for feed in feeds:
                indicators.append(extract_feed_value(feed))

    if indicators:
        logger.info(f'[ANY.RUN] Found {len(indicators)} {indicator_type.upper()} indicators.')
    else:
        logger.warning(f'[ANY.RUN] {indicator_type.upper()} type indicators not found.')

    return indicators


def extract_feed_value(feed: dict) -> str:
    """
    Extracts value from the ANY.RUN indicator

    :param feed: ANY.RUN raw indicator
    :return: Indicator value
    """
    pattern = feed.get("pattern")
    return pattern.split(" = '")[1][:-2]


def make_request(url: str, payload: dict) -> None:
    """
    Executes a requests to the specified endpoints

    :param url: Source URL
    :param payload: HTTP Request body
    :raises RunTimeException: If bad HTTP response is received
    """
    headers = {
        'X-Api-Key': Config.RAPID7_API_KEY,
        'Content-Type': 'application/json'
    }

    response = requests.post(url, headers=headers, json=payload)

    if response.status_code != HTTPStatus.OK:
        message, correlation_id = response.json().get('message'), response.json().get('correlation_id')
        logger.error(f'[Rapid7 API] {message}. Correlation ID: {correlation_id}.')
        raise RunTimeException(f'[Rapid7 API] {message}. Correlation ID: {correlation_id}.', response.status_code)
    else:
        logger.info(f'[Rapid7 API] Loaded {response.json().get("threat").get("indicator_count")} indicators.')

if __name__ == '__main__':
    main()