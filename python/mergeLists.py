import json
import sys

gphotos = []
photoids = {}


for ifpref in sys.argv[1:]:
    ifname = ifpref + ('.json' if not '.json' in ifpref else '')
    photos = json.loads(open(ifname).read())
    for p in photos:
        if not p['id'] in photoids:
            gphotos.append(p)
            photoids[p['id']] = 1

print json.dumps(gphotos, indent=4)

