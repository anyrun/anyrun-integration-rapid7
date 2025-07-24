import os
from dotenv import load_dotenv

load_dotenv()


class Config:
    """ Base configuration class """
    THREAT_FEED_ACCESS_KEY: str = os.environ.get('THREAT_FEED_ACCESS_KEY')

    RAPID7_HOST: str = os.environ.get('RAPID7_HOST')
    RAPID7_API_KEY: str = os.environ.get('RAPID7_API_KEY')

    ANYRUN_BASIC_TOKEN: str = os.environ.get('ANYRUN_BASIC_TOKEN')
    ANYRUN_FEED_FETCH_INTERVAL: int = int(os.environ.get('ANYRUN_FEED_FETCH_INTERVAL'))
    ANYRUN_FEED_FETCH_DEPTH: int = int(os.environ.get('ANYRUN_FEED_FETCH_DEPTH'))

    VERSION: str = 'R7_insightIDR:1.0.0'
    LOGS_FILE_PATH: str = os.path.join(os.path.abspath('logs'), 'anyrun.logs')
