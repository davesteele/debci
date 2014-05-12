require 'set'

require 'debci/status'
require 'debci/package'

module Debci

  # This class implements the backend access to the debci data files. Normally
  # you should access the data through objects of the Debci::Package class,
  # which you can obtain by calling this class' +find_package+ method.
  #
  #     >> repository = Debci::Repository.new
  #     >> package = repository.find_package('mypackage')
  #
  class Repository

    def initialize(path=nil) # :nodoc:
      path ||= Debci.config.data_basedir
      @path = path
      @data_dirs = Dir.glob(File.join(path, '*-*')).reject { |d| d =~ /\.old$/ }
    end

    # Returns an Array of suites known to this debci instance
    def suites
      @suites ||= @data_dirs.map { |d| File.basename(d).split('-').first }.uniq
    end

    # Returns an Array of suites known to this debci instance
    def architectures
      @architectures ||= @data_dirs.map { |d| File.basename(d).split('-').last }.uniq
    end

    # Returns a Set of packages known to this debci instance
    def packages
      @packages ||= @data_dirs.map { |d| Dir.glob(File.join(d, 'packages/*/*')) }.flatten.map { |d| File.basename(d) }.to_set
    end

    # Returns an Array of suites for which there is data for +package+.
    def suites_for(package)
      package = String(package)
      data_dirs_for(package).map { |d| File.basename(d).split('-').first }.uniq
    end

    # Returns an Array of architectures for which there is data for +package+.
    def architectures_for(package)
      package = String(package)
      data_dirs_for(package).map { |d| File.basename(d).split('-').last }.uniq
    end

    class PackageNotFound < Exception
      # :nodoc:
    end

    # Returns a single package by its names.
    #
    # Raises a Debci::PackageNotFound is there is no package with that +name+.
    def find_package(name)
      if !packages.include?(name)
        raise PackageNotFound.new(name)
      end

      Debci::Package.new(name, self)
    end

    # Searches packages by name.
    #
    # Returns an Array of Debci::Package objects. On an exact match, will
    # return an Array with a single element. Otherwise all packages that match
    # the query (which is converted into a regular expression) are returned.
    def search(query)
      # first try exact match
      match = packages.select { |p| p == query }

      # then try regexp match
      if match.empty?
        re = Regexp.new(query)
        match = packages.select { |p| p =~ re }
      end

      match.map { |p| Debci::Package.new(p, self)}
    end

    # Backend implementation for Debci::Package#status
    def status_for(package)
      architectures.map do |arch|
        suites.map do |suite|
          status_file = File.join(data_dir(suite, arch, package), 'latest.json')
          load_status(status_file, suite, arch)
        end
      end
    end

    # Backend implementation for Debci::Package#news
    def news_for(package, n=10)
      suites = '{' + self.suites.join(',') + '}'
      architectures = '{' + self.architectures.join(',') + '}'
      history = Dir.glob(File.join(data_dir(suites, architectures, package), '[0-9]*.json')).sort_by { |f| File.basename(f) }

      news = []

      while !history.empty?
        file = history.pop
        suite_arch = File.basename(File.expand_path(File.dirname(file) + '/../../..'))
        suite, architecture = suite_arch.split('-')
        status = load_status(file, suite, architecture)
        if status.newsworthy?
          news << status
        end
        if news.size >= n
          break
        end
      end

      news
    end

    private

    def data_dir(suite, arch, package)
      File.join(@path, "#{suite}-#{arch}", 'packages', prefix(package), package)
    end

    def prefix(package)
      String(package).sub(/^((lib)?.).*/, '\1')
    end

    def load_status(status_file, suite, architecture)
      status = Debci::Status.from_file(status_file)
      status.suite = suite
      status.architecture = architecture
      status
    end

    def data_dirs_for(package)
      @data_dirs.select { |d| File.exist?(File.join(d, 'packages', prefix(package), package)) }
    end

  end

end
