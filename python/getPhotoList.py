# getPhotoList.py 

# todos:
# * See if I can use a dictionary with flickr.walk call, so I don't have to special case for the below features.
# * Add support for groups, sets users
# * Add support for creative commons / licensing filters


import flickrapi
import re,sys,argparse,json
from flickr_apikey import api_key, api_secret, auth_token

tags = ''
extras = ''

# print argv

# do option parsing here
parser = argparse.ArgumentParser(description='Produce photo lists of tagged photos from Flickr')
parser.add_argument('-l', '--limit', default=4500, type=int, help='maximum photos: default=4500')
parser.add_argument('-g', '--group', default='', help='Group ID') # unused due to lack of API support...
parser.add_argument('-o', '--ofile', default='', help='output file (default=<tags>.json)')
parser.add_argument('tag',  nargs='+', help='tag(s) to search')
args = parser.parse_args()
limit = args.limit
tags = ','.join(args.tag)

ofname = args.ofile
if ofname == '':
    ofname = '+'.join(args.tag) + '.json'
ofname = re.sub(r' ','',ofname)

print "Searching flickr for photos with tags: %s, limit=%d" % (tags,limit)

flickr = flickrapi.FlickrAPI(api_key, api_secret, token=auth_token)

photos = []
knownIDs = {}

nbrRetrieved = 0

for photo in flickr.walk(per_page=min(500,limit), tags=tags, extras=extras):
    # print "ID: %s Title: %s" % (photo.get('id'), photo.get('title'))
    nbrRetrieved += 1
    if nbrRetrieved % 100 == 0:
        print("\r%d..." % (nbrRetrieved)),
        sys.stdout.flush()

    if not photo.attrib['id'] in knownIDs:
        knownIDs[photo.attrib['id']]= 1
        photos.append(photo.attrib)

    if nbrRetrieved >= limit:
        break


# write json dump to file
text_file = open(ofname, "w")
text_file.write(json.dumps(photos, indent=4))
text_file.close()

print "\nWrote %d photos to %s" % (len(photos), ofname)
