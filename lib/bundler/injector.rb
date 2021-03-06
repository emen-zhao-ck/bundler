# frozen_string_literal: true

module Bundler
  class Injector
    def self.inject(new_deps, options = {})
      injector = new(new_deps, options)
      injector.inject(Bundler.default_gemfile, Bundler.default_lockfile)
    end

    def initialize(new_deps, options = {})
      @new_deps = new_deps
      @options = options
    end

    # @param [Pathname] gemfile_path The Gemfile in which to inject the new dependency.
    # @param [Pathname] lockfile_path The lockfile in which to inject the new dependency.
    # @return [Array]
    def inject(gemfile_path, lockfile_path)
      if Bundler.frozen_bundle?
        # ensure the lock and Gemfile are synced
        Bundler.definition.ensure_equivalent_gemfile_and_lockfile(true)
      end

      # temporarily unfreeze
      Bundler.settings.temporary(:deployment => false, :frozen => false) do
        # evaluate the Gemfile we have now
        builder = Dsl.new
        builder.eval_gemfile(gemfile_path)

        # don't inject any gems that are already in the Gemfile
        @new_deps -= builder.dependencies

        # add new deps to the end of the in-memory Gemfile
        # Set conservative versioning to false because we want to let the resolver resolve the version first
        builder.eval_gemfile("injected gems", build_gem_lines(false)) if @new_deps.any?

        # resolve to see if the new deps broke anything
        @definition = builder.to_definition(lockfile_path, {})
        @definition.resolve_remotely!

        # since nothing broke, we can add those gems to the gemfile
        append_to(gemfile_path, build_gem_lines(@options[:conservative_versioning])) if @new_deps.any?

        # since we resolved successfully, write out the lockfile
        @definition.lock(Bundler.default_lockfile)

        # invalidate the cached Bundler.definition
        Bundler.reset_paths!

        # return an array of the deps that we added
        @new_deps
      end
    end

  private

    def conservative_version(spec)
      version = spec.version
      return ">= 0" if version.nil?
      segments = version.segments
      seg_end_index = version >= Gem::Version.new("1.0") ? 1 : 2

      prerelease_suffix = version.to_s.gsub(version.release.to_s, "") if version.prerelease?
      "#{version_prefix}#{segments[0..seg_end_index].join(".")}#{prerelease_suffix}"
    end

    def version_prefix
      if @options[:strict]
        "= "
      elsif @options[:optimistic]
        ">= "
      else
        "~> "
      end
    end

    def build_gem_lines(conservative_versioning)
      @new_deps.map do |d|
        name = d.name.dump

        requirement = if conservative_versioning
          ", \"#{conservative_version(@definition.specs[d.name][0])}\""
        else
          ", #{d.requirement.as_list.map(&:dump).join(", ")}"
        end

        if d.groups != Array(:default)
          group = d.groups.size == 1 ? ", :group => #{d.groups.inspect}" : ", :groups => #{d.groups.inspect}"
        end

        source = ", :source => \"#{d.source}\"" unless d.source.nil?

        %(gem #{name}#{requirement}#{group}#{source})
      end.join("\n")
    end

    def append_to(gemfile_path, new_gem_lines)
      gemfile_path.open("a") do |f|
        f.puts
        f.puts new_gem_lines
      end
    end
  end
end
