class RRD
  def self.test
	puts "test"
  end

  # types are alphanum, num, graph, ds_type, rra_type, path
  def self.sanitize(string,type)
    
    str = ""
    if type == 'num' # 0-9 and . (accepted: 1.5, 10, 234)
       str = string.to_s.match( /[0-9.]+/ )[0]
    elsif type == 'alphanum' # alpha numeric only (accepted: abc123, abc, 123)
       str = string.to_s.match( /[a-zA-Z0-9_\s]+/ )[0]
    elsif type == 'ds_type' # only DS types (accepted values are GAUGE, COUNTER, DERIVE, ABSOLUTE, and COMPUTE
       str = string.to_s.match( /(GAUGE|COUNTER|DERIVE|ABSOLUTE|COMPUTE)/ )[0] rescue RuntimeError
    elsif type == 'rra_type' # only RRA types (accepted values are AVERAGE, MIN, MAX, LAST
       str = string.to_s.match( /(AVERAGE|MIN|MAX|LAST)/ )[0] rescue RuntimeError
    elsif type == 'path' # sanitizes the PATH of the RRD db will match test.rrd and /path/test.rrd
       str = string.to_s.gsub(';', '').gsub('`', '')
    elsif type == 'imagetype'
       str = string.to_s.match(/(PNG|SVG|EPS|PDF)/)[0] rescue RuntimeError #[-a|--imgformat PNG|SVG|EPS|PDF]
    elsif type == 'element'
       str = string.to_s.match(/(PRINT|GPRINT|COMMENT|VRULE|HRULE|LINE|AREA|TICK|SHIFT|TEXTALIGN|STACK)/)[0] rescue RuntimeError
    elsif type == 'color'
      # ACK ground, CANVAS, SHADEA left/top border,
      #SHADEB right/bottom border, GRID, MGRID major grid,
      # FONT, FRAME and axis of the graph or ARROW.
       str = string.to_s.match(/(BACK|CANVAS|SHADEA|SHADEB|GRID|MGRIF|FONT|FRAME|ARROW)/)[0] rescue RuntimeError
    end  

    if str.nil? || str=='RuntimeError'
      raise "No match was returned when matching #{type}"
    else
      return str
    end
  end

  # example usage: 
  # RRD.create('/test.rrd', {:step => 300, :heartbeat => 600,
  # :ds => [  {:name => "test", :type => "GAUGE"}, {:name => "josh", :type => "GAUGE"} ]  ,
  # :xff => ".5", :rra => [ {:type => "max", :steps => 20, :rows => 1} ] })
  # first value is a path to the rrd db, the 2nd param is a hash of keys and values
  # :ds is an array containing hashes for each DataSource (DS) type in the db
  # :xff is the x files factor (see RRD website for more info on this), range is acceptable between 0 and 1
  # :rra is a array containing hashes with RRA types and corresponding values
  # :rra_hwpd is a hwpredict values
  def self.create(path,params,rrdpath="rrdtool")
  	puts "Creating RRD graph"
    puts "Step: " + self.sanitize(params[:step], 'num')
    begin
      cmd = "#{rrdpath} create #{self.sanitize(path, 'path')}"
      cmd << " --start #{self.sanitize(params[:start], 'num')}" if params[:start]
      cmd << " --step #{self.sanitize(params[:step], 'num')}"
      cmd << " --no-overwrite" if params[:no_overwrite]

      for p in params[:ds]
        cmd << " DS:#{p[:name]}:#{self.sanitize(p[:type], 'ds_type')}"
        if p[:ds_name] == "COMPUTE"
          cmd << ":#{p[:rpn]}"
        else
          cmd << ":#{self.sanitize(p[:heartbeat], 'num')}"
          cmd << ":#{p[:min] || '0'}"
          cmd << ":#{p[:max] || 'U'}"
        end
      end

      for r in params[:rra]
        case r[:type]
          when "AVERAGE","MIN","MAX","LAST"
            cmd << " RRA:#{r[:type].upcase}:#{r[:xff]}:#{self.sanitize(r[:steps], 'num')}:#{self.sanitize(r[:rows], 'num')}"
          # hwpredict    RRA:HWPREDICT:1440:0.1:0.0035:288
          # RRA:HWPREDICT:rows:alpha:beta:seasonal period[:rra-num]
          when "HWPREDICT","MHWPREDICT"
            cmd << " RRA:#{r[:type].upcase}:#{r[:rows]}:#{r[:alpha]}:#{r[:beta]}:#{r[:period]}"
            cmd << ":#{r[:rra_num]}" if r[:rra_num]
          when "SEASONAL","DEVSEASONAL"
            cmd << " RRA:#{r[:type].upcase}:#{r[:period]}:#{r[:gamma]}:#{r[:rra_num]}"
            cmd << ":#{r[:windows]}=#{r[:fraction]}" if r[:window] && r[:fraction]
          when "DEVPREDICT"
            cmd << " RRA:#{r[:type].upcase}:#{r[:rows]}:#{r[:rra_num]}"
          when "FAILURES"
            cmd << " RRA:#{r[:type].upcase}:#{r[:rows]}:#{r[:threshold]}:#{r[:window]}:#{r[:rra_num]}"
        end
      end
      
    rescue RuntimeError => e
      puts "RRD failed to create: #{e}"
    else
      cmd << " & "
      puts "Running RRD command: #{cmd}"

      system(cmd)
      return cmd
    end
  end

  # example usage:
  # RRD.update('/test/path.rrd', ["123", "456a", 1234])
  # first param is path to rrd db
  # 2nd param will return data string of 123:456:1234 (each value is sanitized, only numeric values accepted)
  # to be passed as the data values to be passed to the db
  # N specifies the current time (NOW)
  def self.update(path, params,rrdpath="rrdtool")
    # sanitize the params
    begin
      sanitized = []
      params.collect { |p| sanitized << self.sanitize(p, 'num') }
      vals = sanitized[1..-1].join(":")
      cmd = "#{rrdpath} update #{self.sanitize(path, 'path')} "
      cmd << (params[0].blank? ? "N" : params[0])
      cmd << ":#{vals}"
    rescue RuntimeError => e
      puts "RRD failed to update: #{e}"
    else
      puts "Running RRD command #{cmd}"
      system(cmd)
      return cmd
    end
  end

  # variables for DEF's are taken care of programatically
  # required params
  # :ago is when to start from, a Time object ( Time.now )
  # :width, :height
  # :image_type
  # :title
  # :defs => array of hashes
  # # [:defs][:key] => The DB data key
  # # [:defs][:type] => RRA Type
  # # [:defs][:rpn] => RPN Type
  # # [:defs][:color] => Hex Color: (accepts: 001122 but not #001122)
  # # [:defs][:title] => Title for this DEF
  # optional params
  # :base
  # :vlabel
  # :lowerlimit
  # :upperlimit
  # :background --background
  def self.graph(path,image_path,params,rrdpath="rrdtool")
    begin
      cmd = "#{rrdpath} graph #{self.sanitize(image_path, 'path')} "
      unless params[:ago].blank?
        cmd << "-s #{self.sanitize(params[:ago].tv_sec, 'num')} "
      else
        cmd << "-s #{self.sanitize(params[:start].tv_sec, 'num')} "
        cmd << "-e #{self.sanitize(params[:end].tv_sec, 'num')} "
      end
      cmd << "-w #{self.sanitize(params[:width], 'num')} -h #{self.sanitize(params[:height], 'num')} "
      cmd << "-a #{self.sanitize(params[:image_type], 'imagetype')} "
      cmd << "-t '#{self.sanitize(params[:title], 'alphanum')}' "

      abet = "abcdefghijklmnaopqrstuvwxyzABCDEFGHIJKLMNAOPQRSTUVWXYZ".split('')
      # do optionals
      params[:base] ? cmd << " --base=#{self.sanitize(params[:base], 'num')} " : ""
      params[:vlabel] ? cmd << " -v '#{self.sanitize(params[:vlabel], 'alphanum')}' " : ""
      params[:lowerlimit] ? cmd << " --lower-limit=#{self.sanitize(params[:lowerlimit], 'num')} " : ""
      params[:upperlimit] ? cmd << " --upper-limit=#{self.sanitize(params[:upperlimit], 'num')} " : ""
      if params[:color]
         for c in params[:color]
          cmd << " --color #{self.sanitize(c[:type], 'color')}##{self.sanitize(c[:color], 'alphanum')} "
         end
      end

      cmd << "--alt-autoscale-max "

      # load defs
      i = 0
      params[:defs].each do |d|
        d_key = d[:key] || abet[i]
        cmd << "DEF:#{d_key}='#{self.sanitize(path, 'path')}':"
        cmd << "#{self.sanitize(d[:ds_name], 'alphanum')}"
        cmd << ":#{self.sanitize(d[:cf], 'rra_type')} "
        i+=1
      end

      params[:cdefs].each do |c|
        cmd << "CDEF:#{c[:new_key]}=#{c[:key]},#{c[:rpn].join(',')} "
      end unless params[:cdefs].blank? || params[:cdefs].empty?

      params[:elements].each do |e|
        if e[:element] == "COMMENT"
          cmd << " #{self.sanitize(e[:element], 'element')}:\"#{e[:text]}\""
        else
          cmd << " #{self.sanitize(e[:element], 'element')}:#{e[:key]}"
          cmd << "##{self.sanitize(e[:color], 'alphanum')}" unless e[:color].blank?
          cmd << ":#{self.sanitize(e[:cf], 'rra_type')}" unless ["AREA","LINE1"].include?(e[:element])
          cmd << ":\"#{e[:text]}\" "
        end
      end
    rescue RuntimeError => e
      puts "RRD failed to graph: #{e}"
    else
      #cmd << " & "
      puts "Running RRD command: #{cmd}"
      system(cmd)
      return cmd
    end
  end
end
