require "byebug"

class UnusedPartial
  EXT = %w[.html.erb .text.erb .pdf.erb .erb .html.haml .text.haml .haml .rhtml .html.slim slim .liquid]

  def initialize(view_path:)
    @view_path = view_path
  end

  def find
    tree, dynamic = Dir.chdir(@view_path) { used_partials }
    result = ""
    tree.each do |idx, level|
      result += if idx == 1
        "The following partials are not referenced directly by any code:\n"
      else
        "The following partials are only referenced directly by the partials above:\n"
      end
      level[:unused].sort.each do |partial|
        result += "  #{partial}\n"
      end
    end

    unless dynamic.empty?
      result += "Some of the partials above (at any level) might be referenced dynamically by the following lines of code:\n"
      dynamic.sort.map do |file, lines|
        lines.each do |line|
          result += "  #{file}:#{line}\n"
        end
      end
    end
    puts "checks the result.txt file"
    File.write("result.txt", result)
  end

  def used_partials
    files = []
    each_file do |file|
      files << file
    end
    tree = {}
    level = 1
    existent = existent_partials
    top_dynamic = nil
    loop do
      used, dynamic = process_partials(files)
      break if level > 1 && used.size == tree[level - 1][:used].size
      tree[level] = {
        used: used
      }
      if level == 1
        top_dynamic = dynamic
        tree[level][:unused] = existent - used
      else
        tree[level][:unused] = tree[level - 1][:used] - used
      end
      break unless (files - tree[level][:unused]).size < files.size
      files -= tree[level][:unused]
      level += 1
    end
    [tree, top_dynamic]
  end

  def existent_partials
    partials = []
    each_file do |file|
      if /^.*\/_.*$/.match?(file)
        partials << file.strip
      end
    end

    partials
  end

  def each_file(&block)
    files = Dir.glob("**/views/**/*")

    files.each do |file|
      unless File.directory? file
        yield file
      end
    end
  end

  def process_partials(files)
    filename = /[a-zA-Z\d_\/]+?/
    extension = /\.\w+/
    partial = /:partial\s*=>\s*|partial:\s*/
    render = /\brender\s*(?:\(\s*)?/
    esi_include = /\besi_include\s*(?:\(\s*)?/
    liquid_include = /\binclude\s*(?:\(\s*)?/
    partials = []
    dynamic = {}

    files.each do |file|
      File.open(file) do |f|
        f.each do |line|
          line = line
            .encode("UTF-8", "binary", invalid: :replace, undef: :replace, replace: "")
            .strip

          if line =~ %r{(?:#{partial}|#{render}|#{esi_include}|#{liquid_include})(['"])/?(#{filename})#{extension}*\1}
            match = $2
            if match.index("/")

              path = match.split("/")[0...-1].join("/")
              file_name = "_#{match.split("/")[-1]}"
              directory = file.split("/")[0] == "views" ? "views" : file.split("/")[0] + "/views"
              full_path = "#{directory}/#{path}/#{file_name}"
            else
              full_path = "#{file.split("/")[0...-1].join("/")}/_#{match}"
            end
            partials << check_extension_path(full_path)
          elsif /#{partial}|#{render}["']/.match?(line)
            dynamic[file] ||= []
            dynamic[file] << line
          end
        end
      end
    end
    partials.uniq!
    [partials, dynamic]
  end

  def check_extension_path(file)
    file_ext = EXT.find { |e| File.exist?(file + e) }
    return "#{file}#{file_ext}" if file_ext
    file = file.gsub("views", "views/partials").split("/").uniq.join("/")
    "#{file}#{EXT.find { |e| File.exist?(file + e) }}"
  end
end
UnusedPartial.new(view_path: ARGV.first).find
