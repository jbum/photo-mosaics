require 'RMagick'
require 'pp' # for debugging

class FlickrSet
  attr_accessor :photos, :cacheRoot, :downloadOK, :verbose, :dupeOwnersOK

  def initialize(params = {})
    @photos = params.fetch(:photos, [])
    @cacheRoot = params.fetch(:cacheRoot, '')
    @downloadOK = params.fetch(:downloadOK?, true)
    @verbose = params.fetch(:verbose, false)
    @dupeOwnersOK = params.fetch(:dupeOwnersOK, true)
  end

  def make_file_path(idx, minWidth) # used by Mosaick
    suffix = minWidth <= 50? '_t' : ''
    photo = @photos[idx]
    return '' if !photo
    return make_local_path(photo, suffix)
  end

  def get_image(idx, minWidth)  # used by Mosaick
    fname = make_file_path(idx, minWidth)
    return nil if !fname
    if (!File.exists?(fname) or File.size(fname) < 400) and downloadOK
      puts "Image #{fname} seems small at #{File.size(fname)} bytes" if File.exists?(fname)
      download_image(idx, minWidth)
    end
    return nil if !File.exists?(fname)
    return Magick::Image::read(fname).first
  end

  def get_image_webpage(idx)  # used by Mosaick
    photo = @photos[idx]
    return 'http://www.flickr.com/photos/%s/%s/' % [photo['owner'], photo['id']];
  end

  def get_image_desc(idx)  # used by Mosaick
    photo = @photos[idx]
    return 'Photo %s -- click to view' % [photo['id']]
  end

  def get_image_dupeid(idx)  # used by Mosaick
    photo = @photos[idx]
    if dupeOwnersOK
      return photo['id']
    else
      return photo['owner']
    end
  end

  def get_maximages()  # used by Mosaick
    return @photos.length
  end

  def get_image_force(idx) # used by Mosaick
    # !! unimplemented - return forced images
  end

# LOCAL

  def make_local_path(photo, suffix)
    return make_dir_name(photo['id']) + photo['id'] + suffix + ".jpg";
  end

  def make_flickr_path(photo, suffix)
    return sprintf "http://farm%s.static.flickr.com/%d/%s_%s%s.jpg", 
                photo['farm'],photo['server'],photo['id'],photo['secret'],suffix
  end

  def make_url(idx, minWidth)
    suffix = minWidth <= 50? '_t' : ''
    photo = @photos[idx]
    return '' if !photo
    return make_flickr_path(photo, suffix)
  end

  def make_dir_name(id)
    id = id.to_i
    return sprintf 'flickrcache/%03d/%03d/', (id/1000000)%1000, (id/1000)%1000;
  end

  def download_image(idx, minWidth)
    r_path = make_url(idx, minWidth)
    l_path = make_file_path(idx, minWidth)
    build_dirs(l_path)
    puts "Downloading  #{r_path}  --> #{l_path}" if @verbose
    `curl -s #{r_path} >#{l_path}`
  end

  def build_dirs(lname)
    dirs = lname.split(/\//)
    dirs.pop
    ldir = '';
    dirs.each do |d|
      break if d =~ /\.jpg/i
      ldir += '/' if ldir != ''
      ldir += d
      `mkdir #{ldir}` if !File.exists?(ldir)
    end
  end

end

class Mosaick
  attr_accessor :imageset, :max_images, :resoX, :resoY, :cellsize, :noborders, 
    :verbose, :grabThumbs, :doflops, :rootname, :dupesOK, :cspace, 
    :hmode, :hlimit, :hbase, :mixin, :cmode, :anno, :grayscale, 
    :minDupeDist, 
    :tileblur, :tilefilter, :targetblur, 
    :dupeList, :hasForces, :targetfilter, :load, :usevars, 
    :accurate, :draft,
    :filename, :quality, :strip, :png

  def initialize(params = {})
    @max_images = params.fetch(:max_images, 800)
    @imageset = params.fetch(:imageset, nil)
    @reso = params.fetch(:reso, 0)
    @resoX = params.fetch(:resoX, 7)
    @resoY = params.fetch(:resoY, 7)
    @cellsize = params.fetch(:cellsize, 20)
    @noborders = params.fetch(:noborders, false)
    @verbose = params.fetch(:verbose, false)
    @grabThumbs = params.fetch(:grabThumbs, false)
    @doflops = params.fetch(:doflops, false)
    @load = params.fetch(:load, false)
    @rootname = params.fetch(:rootname, 'mosaic')
    @dupesOK = params.fetch(:dupesOK, false)
    @cspace = params.fetch(:cspace, false)  # color space (in bits per component, 0 = normalized)
    @hmode = params.fetch(:hmode, false)  # heatmap mode, with overlapping tiles - unported from perl
    @hlimit = params.fetch(:hlimit, 0) # heatmap image limit 0 = unlimited
    @hbase = params.fetch(:hbase, '')
    @mixin = params.fetch(:mixin, 0).to_i
    @cmode = params.fetch(:cmode, 'Darken')  # also 'Blend'
    @anno = params.fetch(:anno, false)
    @grayscale = params.fetch(:grayscale, false)
    @minDupeDist = params.fetch(:minDupeDist, 8)
    @tileblur = params.fetch(:tileblur, 0.4)
    @tilefilter = params.fetch(:tilefilter, 'Sinc')  # currently unused
    @targetblur = params.fetch(:targetblur, 0.4)
    @dupeList = params.fetch(:dupeList, {})        # used to track duplicates
    @hasForces = params.fetch(:hasForces, false)
    @targetfilter = params.fetch(:targetfilter, 'Sinc') # currently unused
    @basepic = params.fetch(:basepic, '')
    @usevars = params.fetch(:usevars, true)
    @accurate = params.fetch(:accurate, false)
    @draft = params.fetch(:draft, false)
    @filename = params.fetch(:filename, '')
    @quality = params.fetch(:quality, 90)
    @strip = params.fetch(:strip, false)
    @png = params.fetch(:png, false)

    puts "Quality = #{@quality}"
    puts "Mixin = #{@mixin}"

    @cspace = 8 if @hmode and @cspace == 0
    @resoX = @reso if @resoX == 0 and @reso > 0
    @resoY = @resoX if @resoY == 0
    @reso2 = @resoX * @resoY
    @tileAspectRatio = @resoX / @resoY
    @minDupeDist2 = @minDupeDist ** 2
    @basename = @basepic.dup
    @hbase = @basepic.dup if @hmode and @hbase == ''
    @basename.gsub!(/^.*\//, '')
    @basename.sub!(/\.(jpg|png|gif)/,'')

    @sortedcells = []
    @finalimages = []
    @images = []

    puts "BUILDING MOSAIC"
  end

  def setup_cells
    puts "Setting up cells"
    cells = []
    aart = 'BEEEEEEEEEMWWQQQQQQQQQQQNHHHHH@@@@@KKKRRRAA#dddgg88bbbbXXpppPFFFDSSww4444%k9966m222xx$ZhhLLLf&&&V3s55555555ooTuuzvvJJJJJJJJJnclIrrrttjjjjjjj[]]??>><1}}}}}}}}{{{{{="""i/\\\\\\\\\\++++*;;||||!!!!^^^^^^^^^^^^^^^^:::,,,,,,\'\'~~~~~-----____________.......`````````````';
    baseimg = Magick::Image::read(@basepic).first
    w = baseimg.columns
    h = baseimg.rows
    aspect = h/w.to_f
    @targetAspectRatio = aspect
    hcells = Math.sqrt(@max_images / aspect)
    vcells = (hcells * aspect) * @tileAspectRatio
    @hcells = (hcells + 0.5).to_i
    @vcells = (vcells + 0.5).to_i
    if (@hcells*@vcells > @max_images)
      @hcells = hcells.to_i
      @vcells = vcells.to_i
    end
    if @resoX*@hcells > w
      @resoX = (w / @hcells).to_i
      @resoX = 1 if @resoX < 1
      @resoY = (@resoX / @tileAspectRatio).to_i
      @reso2 = @resoX * @resoY
      puts "Forcing Reso to #{@resoX}x#{@resoY} due to lack of resolution in target image"
    elsif @resoY * @vcells > h
      @resoY = (h / @vcells).to_i
      @resoY = 1 if @resoY < 1
      @resoX = (@resoY * @tileAspectRatio).to_i
      @reso2 = @resoX * @resoY
      puts "Forcing Reso to #{@resoX}x#{@resoY} due to lack of resolution in target image"
    end
    puts "Original Image Width #{w} x #{h}" if @verbose
    puts "Allocating Cell Data #{@hcells} x #{@vcells} x #{@resoX}x#{@resoY} (AR=#{@tileAspectRatio})" if @verbose
    baseimg2 = Magick::Image::read(@basepic).first

    # need to do this to convert CMYK images...
    baseimg2.colorspace = Magick::RGBColorspace

    baseimg.resize!(@hcells, @vcells)
    baseimg2.resize!(@hcells*@resoX, @vcells*@resoY)
    if !@hmode
      # normal mode
      puts "Walking Pixels"
      i = 0
      @vcells.times do |y|
        @hcells.times do |x|
          rgb = baseimg.get_pixels(x,y,1,1)[0]
          l = get_haeberli_luminance(rgb)
          hsv = RGBtoHSV(rgb)
          print aart.slice((l*255).to_i,1) * 2
          # puts "rgb = #{rgb.red},#{rgb.green},#{rgb.blue} max=#{Magick::QuantumRange} sat=#{hsv[1]} "
          x0 = x * @resoX
          y0 = y * @resoY
          pix = baseimg2.get_pixels(x0, y0, @resoX, @resoY)
          # puts "Pixels length = #{pix.length}"
          # !! convert to cspace...
          # !! lab color conversion...
          # !! tinting
          cell = { :i => i, :x => x, :y => y, :l => l, :s => hsv[1], :pix => pix }
          cells.push cell
          i += 1
        end
        print "\n"
      end

    else
      # hmode - overlapping cells - experimental
      i = 0
      (@vcells*@resoY-@resoY).times do |y|
        (@hcells*@resoX-@resoX).times do |x|
          rgb = baseimg.get_pixels((x/@resoX).to_i,(y/@resoY).to_i,1,1)[0]
          l = get_haeberli_luminance(rgb)
          hsv = RGBtoHSV(rgb)
          print aart.slice((l*255).to_i,1) * 2 if y % @resoY == 0 && x % @resoX == 0
          pix = baseimg2.get_pixels(x,y,@resoX,@resoY)
          # !! convert to color space
          # !! lab color conversion...
          # !! tinting
          cell = { :i => i, :x => x, :y => y, :l => l, :var => 0, :pix => pix }
          cells.push cell
          i += 1
        end
        print "\n" if y % @resoY == 0
      end
    end

    baseimg.destroy!
    baseimg2.destroy!

    @cells = cells

    if !@hmode
      # sort cells
      @cells.each do |cell|
        cell[:e] = Edginess(cell)
      end
      # sort cells here
      @sortedcells = cells.sort { |a,b| b[:e] <=> a[:e]}
      if @verbose
        n = 0
        @sortedcells.each do |cell|
          # puts "#{n}: e:#{cell[:e]}"
          n += 1
        end
      end
    end
    puts "Done setup cells"
  end

  def make_heatmap(filename)
    setup_cells() if @sortedcells.empty?
    return if @sortedcells.empty?
    width = @resoX * @hcells
    height = @resoY * @vcells
    heatmap = Magick::Image.new(width,height) { self.background_color = 'black' }
    n = 0
    @sortedcells.each do |cell|
      alpha = n.to_f/(@sortedcells.length - 1)
      pix = cell[:pix]
      pi = 0
      @resoY.times do | py |
        @resoX.times do | px |
          r = alpha*pix[pi].red*255/Magick::QuantumRange + 255*(1-alpha)
          g = alpha*pix[pi].green*255/Magick::QuantumRange + 255*(1-alpha)
          b = alpha*pix[pi].blue*255/Magick::QuantumRange + 255*(1-alpha)
          heatmap.pixel_color(cell[:x] * @resoX+px, cell[:y] * @resoY+py, "#%02x%02x%02x" % [r,g,b])
          pi += 1
        end
      end
      n += 1
    end

    heatmap.write(filename)
  end

  def generate_mosaic
    if @finalimages.empty?
      if @load
        load_data()
      elsif @hmode
        select_tiles_hmode()
      else
        select_tiles()
      end
      return if @finalimages.empty?
      save_data() if !@hmode
    end
    # if cellsize is not defined, compute a cellsize which will make us reach minWidth and maxWidth
    if !@cellsize
      if !@minWidth or !@minHeight
        puts "No output dimension defined"
        return
      end
      puts "No explicit cellsize defined\n"
      outputAspectRatio = @minWidth / @minHeight.to_f
      if @targetAspectRatio < outputAspectRatio
        @cellsize = (@minHeight / @vcells / @tileAspectRatio).to_i
      else
        @cellsize = (@minWidth / @hcells).to_i
      end
      @cellsize += 1 if @hcells*@cellsize < @minWidth
      @cellsize += 1 if @vcells*(@cellsize*@tileAspectRatio+0.5).to_i < @minWidth
    end
    @filename = "#{@rootname}_#{@basename}_#{@hcells}_x_#{@vcells}_c#{@cellsize}.jpg" if @filename == ''
    @pngname = @filename.dup
    @pngname.sub!(/\.w+/,'.png')
    @width = @cellsize * @hcells
    @height = (@cellsize / @tileAspectRatio) * @vcells
    cellsizeX = (@width / @hcells + 0.5).to_i
    cellsizeY = (@height / @vcells + 0.5).to_i
    width = cellsizeX * @hcells
    height = cellsizeY * @vcells
    puts "Image Dimensions will be #{width} x #{height} (tiles = #{cellsizeX}x#{cellsizeY} pixels)" if @verbose
    maxCellsize = [cellsizeX,cellsizeY].max
    htmlName = @filename.dup
    htmlName.sub!(/\.jpg/,'.html')

    mosaic = Magick::Image.new(width,height) { self.background_color = 'black' }


    File.open(htmlName,"w") do |f|
      f.write "<img src=\"%s\" usemap=\"#mozmap\" border=0>\n" % [@filename]
      f.write "<map name=\"mozmap\">\n";
      if @strip
        # !! unimplemented
      else
        if !@hmode
          # NORMAL
          @cells.each do |cell|
            imgdat = @finalimages[cell[:iIdx]]
            x = cell[:x]
            y = cell[:y]
            f.write "<AREA SHAPE=rect COORDS=\"%d,%d,%d,%d\" href=\"%s\" TITLE=\"%s\">\n" %
                  [x*cellsizeX,y*cellsizeY,(x+1)*cellsizeX,(y+1)*cellsizeY,
                    @imageset.get_image_webpage(imgdat[:idx]),
                    @imageset.get_image_desc(imgdat[:idx])]
            img = getcroppedphoto(imgdat[:idx], maxCellsize, cell[:var])
            img.colorspace = Magick::RGBColorspace
            img.resize!(cellsizeX,cellsizeY)
            img.flop! if cell[:flop]
            mosaic.composite!(img,x*cellsizeX,y*cellsizeY,Magick::OverCompositeOp)
            img.destroy!
            if @anno
              text = Magick::Draw.new
              pointsize = (cellsizeX * 0.33).to_i
              pointsize = [9,pointsize].max
              label = '%c%d' % [65+x,y+1]
              text.annotate(mosaic, cellsizeX, cellsizeY, x*cellsizeX+1, y*cellsizeY+1, label) {
                  self.gravity = Magick::NorthWestGravity
                  self.pointsize = pointsize
                  self.stroke = 'transparent'
                  self.fill = '#FFF'
                  self.text_antialias = true
                  self.undercolor = '#00000044'
                  }


            end

          end

        else
          # !! HMODE - images are allowed to overlap
          if (@hbase != '')
            mosaic = Magick::Image::read(@hbase).first
            mosaic.resize!(width,height)
          end
          i = 0
          @finalimages.each do |imgdat|
            cell = @cells[imgdat[:cellIdx]]
            x = cell[:x]
            y = cell[:y]
            f.write "<AREA SHAPE=rect COORDS=\"%d,%d,%d,%d\" href=\"%s\" TITLE=\"%s\">\n" %
                  [x*cellsizeX,y*cellsizeY,(x+1)*cellsizeX,(y+1)*cellsizeY,
                    @imageset.get_image_webpage(imgdat[:idx]),
                    @imageset.get_image_desc(imgdat[:idx])]
            img = getcroppedphoto(imgdat[:idx], maxCellsize, cell[:var])
            img.colorspace = Magick::RGBColorspace
            img.resize!(cellsizeX,cellsizeY)
            img.flop! if cell[:flop]
            mosaic.composite!(img,x*cellsizeX/@resoX,y*cellsizeY/@resoY,Magick::OverCompositeOp)
            img.destroy!
            i += 1
            puts "#{i}" if i % 500 == 0
          end
        end
      end
      f.write "</map>"
    end # file closes here

    if @mixin > 0
      # faster version of mixin
      bgpic = Magick::Image::read(@basepic).first
      bgpic.resize!(width,height)
      puts "Mixing in #{@mixin}..."
      mosaic = mosaic.blend(bgpic,@mixin/100.0)
      bgpic.destroy!
    end

    mosaic = mosaic.quantize(256, Magick::GRAYColorspace) if @grayscale

    mosaic.write @pngname if @png
      
    puts "Saving JPEG #{@filename}" if @verbose
    myquality = @quality
    mosaic.write(@filename) { self.quality = myquality }
    # mosaic.write(@filename) {  }
    mosaic.destroy!
  end

  def select_tiles_hmode
    sample_photos() if @images.empty?
    return if @images.empty?

    setup_cells()
    return if @cells.empty?

    numImages = @images.length
    maximages = @images.length
    nbrImagesMatched = 0

    lastImageIdx = numImages-1
    unplacedImages = @images.dup
    nbrPlaced = 0
    hPass = 0

    while unplacedImages.length > 0 and nbrImagesMatched < maximages
      hPass += 1
      puts(hPass)
      nbrUnplaced = 0
      unplacedImages.length.times do |i|
        puts " placing image #{i}"
        image = unplacedImages[i]
        next if image.has_key?(:placed)
        subsample_photo(image)
        if image.has_key?(:cellIdx)
          cell1 = @cells[image[:cellIdx]]
          overlaps = false
          i.times do |j|
            image2 = unplacedImages[j]
            next if not image2.has_key?(:cellIdx)
            cell2 = @cells[image2[:cellIdx]]
            if CellsOverlap(cell1,cell2)
              overlaps = true
              break
            end
          end
          if !overlaps
            push @fimages, image
            image[:placed] = true
            nbrImagesMatched += 1
            break if nbrImagesMatched >= maxImages
            cell1 = @cells[image[:cellIdx]]
            @cells.each do |cell2|
              if CellsOverlap(cell1,cell2)
                cell2[:used] = 1
              end
            end
            next
          else
            puts "Image #{i} overlaps, replacing"
          end
        end
        nbrUnplaced += 1
        minDiff = -1
        gotOne = false
        puts "Looking at cells"
        @cells.each do | ucrec |
          diff = CumDiff(image,ucrec,minDiff,0)
          if diff < minDiff
            minDiff = diff
            cIdx = ucrec[:i]
            flop = 0
            var = 0
            gotOne = 1
          end
        end
        if gotOne
          image[:cellIdx] = cIdx
          image[:cDist] = minDiff
        end
      end
      unplacedImages = unplacedImages.sort { |a,b| a[:cDist] <=> b[:cDist]}
    end
    fimages = fimages.sort { |a,b| b[:cDist] <=> a[:cDist] }
    @finalimages = fimages
    @images = []
    @iIndex = []
  end

  def CellsOverlap(cell1,cell2)
    x1 = cell1[:x]
    y1 = cell1[:y]
    x2 = cell2[:x]
    y2 = cell2[:y]
    w = @resoX
    h = @resoY
    return false if x1 >= x2+@resoX
    return false if x1+@resoX <= x2
    return false if y1 >= y2+@resoY
    return false if y1+@resoY <= y2
    return true
  end

  def select_tiles
    sample_photos() if @images.empty?
    return if @images.empty?

    setup_cells() if @sortedcells.empty?
    return if @sortedcells.empty?

    numImages = @images.length
    lastImageIdx = numImages-1
    puts "Selecting from #{numImages} images... #{@sortedcells.length} cells\n" if @verbose

    BuildLumIndex()

    i = 0
    lErr = 0
    fimages = []

    startSecs = Time.now

    imagesPerSlot = numImages.to_f/256

    maxLumErr = 0
    maxDiff = 0

    @sortedcells.each do |cell|
      # puts "tile #{i} cell #{cell[:x]} x #{cell[:y]} " if @verbose
      cIdx = 0
      minDiff = -1
      flop = false
      var = 0
      gotOne = false

      # this computes a number of slots based on a desired number of images which ranges from 300 to 100
      # using extra candidates for images which are earlier in the array (and edgier)

      lErr = 20 # worked this out experimentally - normal mode
      lErr = 5 if @draft      # worked out experimentally
      lErr = 40 if @accurate  # worked this out experimentally

      # add bonus here based on edginess...
      # lErr += 20 + cell[:e].to_f/@reso2
      while !gotOne
        ii = (cell[:l] * 255).to_i
        mini = @iIndex[ii - lErr < 0? 0 : ii - lErr]
        maxi = @iIndex[ii + lErr > 255? 255 : ii + lErr]
        # puts "  ii = #{ii} lErr = #{lErr} fmin-max = #{mini}-#{maxi}" if @verbose
        if maxi - mini < 256
          mini -= 128
          maxi += 128
        end
        mini = 0 if mini < 0
        maxi = lastImageIdx if maxi > lastImageIdx || ii+lErr >= 255
        # puts "  min-max = #{mini}-#{maxi}" if @verbose

        # tried various tricks to reorder candidates to get more bounds clipping.  didn't shorten execution time
        cands = (mini..maxi).to_a   #.sort {|a,b| (@images[a][:l]-cell[:l]).abs <=> (@images[b][:l]-cell[:l]).abs }
        # swap in a middling candidate to get a better lower bound
        # med = (cands.length/2).to_i
        # 10.times  { |j|
        #   t = cands[med+j]
        #   cands[med+j] = cands[j]
        #   cands[j] = t
        # }

        cands.each do |j|
        # (mini..maxi).each do |j|



          image = @images[j]

          # optimization... doesn't help
          # lumDiff = ((image[:l]*255).to_i-ii).abs
          # minPossibleDiff = lumDiff == 0? 0 : (@resoX*@resoY*3*(lumDiff-1))+1
          # next if minDiff > 0 && minPossibleDiff > minDiff

          next if image[:xx]
          next if GetMinDupeDist2(image, cell[:x], cell[:y]) < @minDupeDist2
          # pp image
          subsample_photo(image) # subsample photo if we haven't yet

          3.times do |v| # variations
            next if v > 0 and !@usevars
            diff = CumDiff(image,cell,minDiff,v)
            if diff < minDiff or minDiff == -1
              minDiff = diff
              cIdx = j
              flop = false
              var = v
              gotOne = true
            end
            if @doflops
              diff = CumDiffFlop(image,cell,minDiff,v)
              if diff < minDiff or minDiff == -1
                minDiff = diff
                cIdx = j
                flop = true
                var = v
                gotOne = true
              end
            end
          end # end v loop (variations)
        end # end j loop
        # if no match found, widen range
        lErr += 5
      end


      cPhoto = @images[cIdx]

      lumErr = (cPhoto[:l] - cell[:l]).abs
      maxLumErr = [lumErr,maxLumErr].max
      maxDiff = [minDiff,maxDiff].max

      cPhoto[:i] = cell[:i]
      cell[:iIdx] = fimages.length
      cell[:img] = cPhoto
      cell[:flop] = flop
      cell[:var] = var
      cell[:diff] = minDiff
      fimages.push cPhoto

      # handle dupes
      cPhoto[:xx] = !@dupesOK
      cPhoto[:placed] = true

      dupeCoords = @dupeList[ @imageset.get_image_dupeid(cPhoto[:idx]) ]
      drec = { :x => cell[:x], :y => cell[:y] }
      dupeCoords.push drec

      i += 1

      puts "#{i}..." if i % 100 == 0 && @verbose

    end
    puts "Done main pass elapsed: %.2f seconds" % [Time.now - startSecs]
    puts "Max Lum Err: %.1f   Max Diff: %d" % [maxLumErr * 256, maxDiff]

    if @hasForces
      # !! place remaining forced images, unimplemented
      # !! this flag forces a subset of tiles to appear in the mosaic, regardless of their suitability
      # code finds least objectionable positions for each of these tiles, and places them
    end

    # renumber final images here
    fimages = []
    @cells.each do |cell|
      cell[:iIdx] = fimages.length
      fimages.push cell[:img]
    end

    @finalimages = fimages
    @images = []
    @iIndex = []
    @sortedcells = []
  end

  def sample_photos
    images = []
    maxImages = @imageset.get_maximages()
    puts "Sampling #{maxImages} source images..." if @verbose
    maxReso = [@resoX,@resoY].max
    maxImages.times do |idx|
      begin
        image = @imageset.get_image(idx, maxReso)
        w = image.columns
        h = image.rows
        badImage = false
        if @noborders
          w1 = w-1
          h1 = h-1
          w2 = (w/2).to_i
          h2 = (h/2).to_i

          rgb1 = image.get_pixels(w2,0,1,1)[0]  # top center
          rgb2 = image.get_pixels(w2,h1,1,1)[0] # bot center
          rgb3 = image.get_pixels(0,h2,1,1)[0] # left center
          rgb4 = image.get_pixels(w1,h2,1,1)[0] # right center
          d1 = (rgb2.red - rgb1.red)**2 +
               (rgb2.green - rgb1.green)**2 +
               (rgb2.blue - rgb1.blue)**2
          d1 = d1.to_f / Magick::QuantumRange
          d2 = (rgb4.red - rgb3.red)**2 +
               (rgb4.green - rgb3.green)**2 +
               (rgb4.blue - rgb3.blue)**2
          d2 = d1.to_f / Magick::QuantumRange
          if d1 <= 0.007 or d2 <= 0.007 or w.to_f/h >= 2 || h.to_f/w >= 2
            badImage = true
            print '.' if @verbose
          end
        end
        if not badImage
          image.resize!(1,1)
          rgb = image.get_pixels(0,0,1,1)[0]
          l = get_haeberli_luminance(rgb)
          photo = {:idx => idx, :l=>l}
          photo[:force] = @imageset.get_image_force(idx) if @hasForces
          images.push photo
        end
        image.destroy!
      rescue
      puts "Problem with image: #{@imageset.make_file_path(idx, maxReso)}"
      end
      puts "#{idx+1}..." if (idx+1) % 500 == 0 && @verbose
    end
    puts "Got #{images.length} images"
    @images = images
  end

  def subsample_photo(photo)
    # print "Subsampling "
    # pp photo

    if !photo.has_key?(:pix) or photo[:pix].length == 0
      photo[:pix] = []
      key = @imageset.get_image_dupeid(photo[:idx])
      @dupeList[ key ] = [] if not @dupeList.has_key?(key)
      3.times do |v| # variations
        next if v > 0 and !@usevars
        image = getcroppedphoto(photo[:idx], @resoX, v)
        image.resize!(@resoX, @resoY)
        pix = image.get_pixels(0,0,@resoX,@resoY)
        # !! color space conversion
        # !! lab handling
        photo[:pix].push pix
        image.destroy!
      end
    end
  end

  def getcroppedphoto(idx, resoX, var)
    image = @imageset.get_image(idx,resoX)
    if image.nil?
      puts "Problem getting image #{idx}"
      return nil
    end
    # crop to square
    w = image.columns
    h = image.rows
    if var == 0
      if w/h.to_f < @tileAspectRatio
        nh = w / @tileAspectRatio
        image.crop!(0,(h-nh)/2,w,nh)
      elsif w/h > @tileAspectRatio
        nw = h * @tileAspectRatio
        image.crop!((w-nw)/2,0,nw,h)
      end
    elsif var == 1 # left/top
      if w/h.to_f < @tileAspectRatio
        nh = w / @tileAspectRatio
        image.crop!(0,0,w,nh)
      elsif w/h > @tileAspectRatio
        nw = h * @tileAspectRatio
        image.crop!(0,0,nw,h)
      end
    else # var == 2 # right/bot
      if w/h.to_f < @tileAspectRatio
        nh = w / @tileAspectRatio
        image.crop!(0,(h-nh),w,nh)
      elsif w/h > @tileAspectRatio
        nw = h * @tileAspectRatio
        image.crop!((w-nw),0,nw,h)
      end
    end
    return image
  end

  def GetMinDupeDist2(img,x,y)
    mind = 100000000
    key = @imageset.get_image_dupeid(img[:idx])
    return mind if !@dupeList.has_key?(key)
    dupeCoords = @dupeList[key]
    dupeCoords.each do | dd |
      dx = (dd[:x] - x) ** 2
      dy = (dd[:y] - y) ** 2
      mind = dx if dx == 0
      mind = dy if dy == 0
      mind = dx+dy if dx+dy < mind
    end
    return mind
  end

  def BuildLumIndex
    @images.sort! { |a,b| a[:l] <=> b[:l]} 
    iIndex = []
    lIdx = -1
    n = 0
    j = 0
    puts "Sorting #{@images.length} images for luminance" if @verbose
    @images.each do |img|
      if (img[:l]*255).to_i != lIdx
        lIdx = (img[:l]*255).to_i 
        while n <= lIdx
          iIndex[n] = j
          n += 1
        end
      end
      j += 1
    end
    while n <= 255
      iIndex[n] = j
      n += 1
    end
    puts "Lumindex has #{n} entries" if $verbose
    @iIndex = iIndex
  end

  def BuildLumIndex_hmode
    BuildLumIndex()
  end


  def load_data
    savefilename = "%s_%s_mosaick.json" % [@rootname, @basename]
    sdata = JSON.parse(File.read(savefilename))
    @basepic = sdata['basepic']

    @hcells = sdata['hcells']
    @vcells = sdata['vcells']
    @tileAspectRatio = sdata['tileAspectRatio']
    @targetAspectRatio = sdata['targetAspectRatio']
    @cells = []
    sdata['cells'].each do |cell|
     @cells.push( {:x => cell['x'],
                           :y => cell['y'],
                           :iIdx => cell['iIdx'],
                           :var => cell['var'],
                           :flop => cell['flop'] })
    end
    @finalimages = []
    sdata['finalimages'].each do |img|
      @finalimages.push({ :idx => img['idx'], :desc => img['desc'] })
    end

  end

  def save_data
    sdata = { :basepic => @basepic,
              :hcells => @hcells,
              :vcells => @vcells,
              :tileAspectRatio => @tileAspectRatio,
              :targetAspectRatio => @targetAspectRatio,
              :cells => [],
              :finalimages => [] }

    @cells.each do |cell|
      sdata[:cells].push( {'x' => cell[:x],
                           'y' => cell[:y],
                           'iIdx' => cell[:iIdx],
                           'var' => cell[:var],
                           'flop' => cell[:flop] })
    end

    @finalimages.each do |img|
      sdata[:finalimages].push({ 'idx' => img[:idx], 'desc' => @imageset.get_image_desc(img[:idx]) })
    end
    savefilename = "%s_%s_mosaick.json" % [@rootname, @basename]
    File.open(savefilename,"w") do |f|
      f.write(JSON.pretty_generate(sdata))
    end
  end

  def get_haeberli_luminance(rgb)
    return (0.3086*rgb.red + 0.6094*rgb.green + 0.0820*rgb.blue)/Magick::QuantumRange # Haeberli luminance calc
  end

  def RGBtoHSV(rgb) # assumes r,g,b are normalized
    r = rgb.red.to_f / Magick::QuantumRange
    g = rgb.green.to_f / Magick::QuantumRange
    b = rgb.blue.to_f / Magick::QuantumRange
    max = [r,g,b].max
    min = [r,g,b].min
    v = max
    s = (max != 0)? (max-min)/max : 0
    h = 0
    if (s != 0) 
      d = max - min
      if r == max
        h = (g - b)/d
      elsif g == max
        h = 2 + (b-r)/d
      elsif b == max
        h = 4 + (r-g)/d
      end
      h *= 60
      h += 360 if (h < 0);
    end
    return [h/360,s,v]
  end

  def CumDiff(img,cell,upperBound,var)
     sum = 0
     pix1 = cell[:pix]
     pix2 = img[:pix][var]
     @reso2.times do |i|
        sum += (pix1[i].red - pix2[i].red) ** 2 + 
               (pix1[i].green - pix2[i].green) ** 2 + 
               (pix1[i].blue - pix2[i].blue) ** 2
        # speeds us up to 40%
        break if upperBound > 0 and sum > upperBound        
     end
     return sum
  end

  def CumDiffFlop(img,cell,upperBound,var)
     sum = 0
     pix1 = cell[:pix]
     pix2 = img[:pix][var]
     r = @resoX
     @reso2.times do |i|
        x = i % r
        y = (i / r).to_i
        i2 = y*r + (r-1)-x
        sum += (pix1[i].red - pix2[i2].red) ** 2 + 
               (pix1[i].green - pix2[i2].green) ** 2 + 
               (pix1[i].blue - pix2[i2].blue) ** 2
        # speeds us up to 40%
        break if upperBound > 0 and sum > upperBound        
     end
     return sum
  end



  def Edginess(cell)
    pix = cell[:pix]
    cumdiff = 0
    resoX = @resoX

    @reso2.times do |i|
      x = i % @resoX
      y = (i / @resoX).to_i
      if y > 0
        j = i - @resoX
        cumdiff += ((pix[j].red - pix[i].red) ** 2 + (pix[j].green - pix[i].green) ** 2 + (pix[j].blue - pix[i].blue) ** 2).to_f / Magick::QuantumRange
      end
      if y < @resoY-1
        j = i + @resoX
        cumdiff += ((pix[j].red - pix[i].red) ** 2 + (pix[j].green - pix[i].green) ** 2 + (pix[j].blue - pix[i].blue) ** 2).to_f / Magick::QuantumRange
      end
      if x > 0
        j = i - 1
        cumdiff += ((pix[j].red - pix[i].red) ** 2 + (pix[j].green - pix[i].green) ** 2 + (pix[j].blue - pix[i].blue) ** 2).to_f / Magick::QuantumRange
      end
      if x < @resoX-1
        j = i + 1
        cumdiff += ((pix[j].red - pix[i].red) ** 2 + (pix[j].green - pix[i].green) ** 2 + (pix[j].blue - pix[i].blue) ** 2).to_f / Magick::QuantumRange
      end
    end
    return cumdiff
  end


end