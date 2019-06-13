from enum import Enum
import os
import sys
import logging


# In case this will need to run on Windows systems
if sys.platform.lower() == "win32":
    os.system('color')


class AvailableColors(Enum):
    GRAY = 90
    RED = 91
    GREEN = 92
    YELLOW = 93
    BLUE = 94
    PURPLE = 95
    WHITE = 97
    BLACK = 30
    DEFAULT = 39


STYLE_MAPPING = {
    'DEBUG': 'GRAY',
    'INFO': 'DEFAULT',
    'WARNING': 'YELLOW',
    'ERROR': 'PURPLE',
    'CRITICAL': 'RED',
}


def dye_msg_with_color(msg: str, color: str) -> str:
    """Dye message with color, fall back to default if it fails."""
    color_code = AvailableColors['DEFAULT'].value
    try:
        color_code = AvailableColors[color.upper()].value
    except KeyError:
        pass
    return f"\033[{color_code}m{msg}\033[0m"


def dye_logger(
    logger: logging.Logger, style_mapping: dict = STYLE_MAPPING
) -> logging.Logger:
    """Dye a logger with colors according to the style_mapping dict.

    Derived from: https://gist.github.com/herrkaefer/3582e2ab5a344647e325782e1a1f3c84
    """
    try:
        if logger.dyed:
            return logger
    except AttributeError:

        def _dye_logging_func(logging_func, color):
            def logging_func_wrapper(msg, *args, **kwargs):
                logging_func(dye_msg_with_color(msg, color), *args, **kwargs)

            return logging_func_wrapper

        for func_name, color_name in style_mapping.items():
            setattr(
                logger,
                func_name.lower(),
                _dye_logging_func(getattr(logger, func_name.lower()), color_name),
            )
        setattr(logger, 'dyed', True)
        return logger
