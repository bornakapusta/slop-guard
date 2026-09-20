# frozen_string_literal: true

module SlopGuard
  # One entry of a Git tree listing, from either the local plumbing or the GitHub API. `classify` applies the
  # shared inspection rules in one order; each source decides what a gap, a skip or an oversize means for it.
  class TreeEntry < Data.define(:path, :mode, :type, :size, :oid)
    SUBMODULE_MODE = '160000'
    BLOB_MODES = %w[100644 100755].freeze

    def classify(profile)
      return :submodule if mode == SUBMODULE_MODE
      return :skipped unless profile.permitted?(path)
      return :non_regular unless type == 'blob' && BLOB_MODES.include?(mode)
      return :oversized if size && size > Limits::FILE_BYTES

      :blob
    end
  end
end
