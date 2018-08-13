#!/usr/bin/env python3

# This script demonstrates the use of ste.py as a module.
# You can try it like this:
#   export "PYTHONPATH=:/home/dbooth/rdf-pipeline/trunk/tools"
#   ./module-invoker.py setup-files/sample-template.txt

import ste
import sys

# Map template variables to values:
tmap = { 'file:///tmp/foo.ttl': 'file:///tmp/BAR.ttl',
         'urn:local:foo': 'urn:local:BAR' }

if __name__ == '__main__':
    with open(sys.argv[1], "r", encoding='utf-8') as f:
        template = f.read()
        result = ste.ExpandTemplate(template,  tmap)
        print('================== OLD ====================\n'+template)
        print('================== NEW ====================\n'+result)
    sys.exit(0)

