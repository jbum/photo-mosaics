# Flickr Image Downloader - supports multiple threads
# make buildDirs lock, so we don't hit it twice...

import json
import requests
import argparse
import sys, os, threading
from subprocess import call
from time import sleep

class DownloaderThread(threading.Thread):
  def __init__(self, idx, photoList):
    threading.Thread.__init__(self)
    self.photoList = photoList
    self.done = False
    self.idx = idx
    self.ne = 0
    self.n = 0

  def makeFlickrPath(self, photo, suffix):
     return "http://farm%s.static.flickr.com/%s/%s_%s%s.jpg" % (
                 photo['farm'],photo['server'],photo['id'],photo['secret'],suffix)

  def makeDirName(self, id):
    id = int(id)
    return 'flickrcache/%03d/%03d/' % ((id/1000000)%1000, (id/1000)%1000)

  def makeLocalPath(self, photo, suffix):
    return self.makeDirName(photo['id']) + photo['id'] + suffix + ".jpg"

  def buildDirs(self, lname):
    dirs = lname.split('/')
    dirs.pop()
    ldir = ''
    for d in dirs:
      if '.jpg' in d:
        break
      if ldir != '':
        ldir += '/'
      ldir += d
      if not os.path.exists(ldir):
        os.mkdir(ldir)

  def downloadImage(self,url, path):
    if os.path.exists(path):
      # print "got",filename
      return
    self.buildDirs(path)
    r = requests.get(url)
    if r.status_code != 200:
      print r.status_code,"on",url
    else:
      imgFile = open(path, "w")
      imgFile.write(r.content)
      imgFile.close()
      print url,"-->",path

  def run(self):
    for p in self.photoList:
      url_b = self.makeFlickrPath(p, suffix)
      l_path = self.makeLocalPath(p, suffix)
      if os.path.exists(l_path) and os.path.getsize(l_path) > 100:
        self.ne += 1
        continue
      self.downloadImage(url_b, l_path)
      self.n += 1
    self.done = True
    # print "Thread",self.idx,"Done"


parser = argparse.ArgumentParser(description='Retrieve thumbnails from Flickr')
parser.add_argument('-b', '--big', default=False, action='store_true', help='Get larger photos')
parser.add_argument('-r', '--reverse', default=False, action='store_true', help='Reverse order of photos')
parser.add_argument('-v', '--verbose', default=False, action='store_true', help='Verbose messages')
parser.add_argument('ifile',  nargs='+', help='file(s) to retreive images from')
args = parser.parse_args()

suffix = '' if args.big else '_t'
verbose = args.verbose
reverse = args.reverse

nbrDownloaded = 0
nbrSkipped = 0

for ifprefix in args.ifile:
  ifname = ifprefix

  if not '.json' in ifname:
    ifname += '.json'

  if not os.path.exists(ifname):
    print "File %s does not exist"
    sys.exit()

  if verbose:
    print "Photo list: " + ifname

  photos = json.loads(open(ifname).read())


  nbrThreads = 8
  partition = len(photos)/nbrThreads + 1
  threads = []
  for i in range(nbrThreads):
    t = DownloaderThread(i,photos[partition*i:partition*i+partition+1])
    t.daemon = True # insures thread dies with main process, if necessary
    t.start()
    threads.append(t)

  allDone = False
  while not allDone:
    allDone = True
    sleep(2)
    for thread in threads:
      if not thread.done:
        allDone = False
        break

  for thread in threads:
    nbrDownloaded += thread.n
    nbrSkipped += thread.ne

if nbrDownloaded > 0 and verbose:
  print "Downloaded %d thumbnails" % (nbrDownloaded)
if nbrSkipped > 0 and verbose:
  print "%d thumbs already exist" % (nbrSkipped)




