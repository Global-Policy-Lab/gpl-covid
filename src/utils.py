from . import __file__ as pkg_init_name
from pathlib import Path

HOME = Path(pkg_init_name).parent.parent
DATA = HOME / 'data'
DATA_RAW = DATA / 'raw'
DATA_PROCESSED = DATA / 'processed'
DATA_INTERIM = DATA / 'interim'

ISOS = ['USA','ITA','FRA','CHN','KOR','IRN']

adm3_dir_fmt = 'gadm36_{iso3}_{datestamp}'

def iso_to_dirname(iso3):
    mapping = {
        "FRA": "france",
        "ITA": "italy",
        "USA": "usa",
        "CHN": "china",
        "IRN": "iran",
        "KOR": "korea"
    }
    return mapping[iso3]
    
def get_adm3_dir(iso3, datestamp):
    dirname = iso_to_dirname(iso3)
    assert (DATA_RAW / dirname).is_dir(), DATA_RAW / dirname
    return DATA_RAW / dirname / adm3_dir_fmt.format(iso3=iso3, datestamp=datestamp)