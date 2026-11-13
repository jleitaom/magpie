#!/bin/zsh
# Flags spacing numbers off the 4 pt grid, views nudged with offset or position, and (outside the
# design kit) literal icon sizes, shadow numbers and CGFloat constants, which belong in Metric.
# Usage: scripts/grid-lint.sh [folder]      (default: Sources)
# Allowed numbers: 0, 1, 2, and multiples of 4. Better: a token (Space.lg, theme.radius.md).
# The token files (Theme.swift, Grid.swift, and a design kit's Tokens.swift) are skipped.
# Silence one line with a reason: // grid: ok <why>
set -euo pipefail
dir=${1:-${0:A:h:h}/Sources}
find "$dir" -name '*.swift' -not -name 'Theme.swift' -not -name 'Grid.swift' -not -name 'Tokens.swift' -print0 | xargs -0 perl -ne '
  BEGIN { $count = 0 }
  if (!/grid: ok/) {
    my @bad;
    while (/(?:\.padding\((?:\.\w+|\[[^\]]*\])?,?\s*|spacing:\s*|(?:min|max|ideal)?(?:[Ww]idth|[Hh]eight):\s*|cornerRadius:\s*)(-?\d+(?:\.\d+)?)\b/g) {
      my $n = $1;
      push @bad, $n unless $n == 0 || $n == 1 || $n == 2 || ($n == int($n) && $n % 4 == 0);
    }
    # Outside the design kit and the debug tools, sizes have names: no literal icon size,
    # shadow radius or drop, or CGFloat constant in a view (Metric.* instead).
    if ($ARGV !~ m{/(DesignKit|Debug|MagpieKit)/}) {
      push @bad, "icon size $1" if /KitIconView\([^)]*\bsize:\s*(\d+(?:\.\d+)?)/;
      push @bad, "shadow $1" if /\.shadow\([^)]*\b(?:radius|x|y):\s*(-?\d+(?:\.\d+)?)\b/;
      push @bad, "constant $1" if /:\s*CGFloat\s*=\s*(-?\d+(?:\.\d+)?)\b/ && $1 > 2;
    }
    push @bad, "offset" if /\.offset\(/;
    push @bad, "position" if /\.position\(/;
    if (@bad) { $count++; my $l = $_; $l =~ s/^\s+//; print "$ARGV:$.: off grid (", join(", ", @bad), "): $l"; }
  }
  close ARGV if eof;
  END { if ($count) { print "FAIL grid-lint: $count lines off the grid\n"; exit 1 } print "PASS grid-lint\n" }'
