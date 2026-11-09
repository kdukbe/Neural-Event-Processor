"""Local tool discovery and isolated build paths for reproduction scripts."""
import os
from pathlib import Path
import shutil

PROJECT = Path(__file__).resolve().parents[1]


def build_root(value=None):
    return Path(value or os.environ.get('NEURAL_BUILD_DIR') or PROJECT / 'build').expanduser().resolve()


def vivado_bin(value=None):
    location = value or os.environ.get('NEURAL_VIVADO_BIN')
    if not location and os.environ.get('XILINX_VIVADO'):
        location = Path(os.environ['XILINX_VIVADO']) / 'bin'
    if not location:
        executable = shutil.which('vivado.bat')
        if executable:
            location = Path(executable).parent
    if not location:
        raise ValueError('Vivado not found. Use its command prompt, --vivado-bin, or NEURAL_VIVADO_BIN.')
    directory = Path(location).expanduser().resolve()
    required = [directory / name for name in ('vivado.bat', 'xvlog.bat', 'xelab.bat', 'xsim.bat')]
    required.append(glbl_source(directory))
    missing = [str(path) for path in required if not path.is_file()]
    if missing:
        raise ValueError('Incomplete Vivado installation: ' + ', '.join(missing))
    return directory


def glbl_source(directory):
    return Path(directory).parent / 'data/verilog/src/glbl.v'
