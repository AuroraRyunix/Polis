# Polis - the Windows road to a printer.
#
# Run by Polis.Printer.Windows with Windows PowerShell 5.1 (powershell.exe),
# which every Windows 10 and 11 has. Nothing is installed and nothing is
# bundled: System.Drawing.Printing draws the page through the printer's own
# driver, in Arial, which has every letter a player's name is likely to
# need. Why not print the PDF instead: Windows has no PDF print verb of its
# own, and the one it borrows belongs to whatever PDF reader is installed,
# if any, and opens a window doing it. See lib/polis/printer.ex.
#
#   -Action printers          one printer name per line
#   -Action default           the default printer's name
#   -Action print -Job FILE   draws the job in FILE (JSON, see
#                             Polis.Printer.Windows.job_json/1); "ok" when
#                             the spooler took it, otherwise one line of why
#
# Coordinates in the job are PDF points: origin at the bottom left of the
# sheet, y going up, a text's y its baseline. This file turns them into
# what System.Drawing wants (origin top left, y going down, a text's y the
# top of its cell). Keep it ASCII: Windows PowerShell reads a file without
# a byte order mark in the machine's ANSI code page.

param(
  [Parameter(Mandatory = $true)][ValidateSet('printers', 'default', 'print')][string]$Action,
  [string]$Job
)

$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

function Say([string]$line) { [Console]::Out.WriteLine($line) }

try {
  Add-Type -AssemblyName System.Drawing

  switch ($Action) {
    'printers' {
      foreach ($name in [System.Drawing.Printing.PrinterSettings]::InstalledPrinters) { Say $name }
      exit 0
    }

    'default' {
      $settings = New-Object System.Drawing.Printing.PrinterSettings
      if ($settings.IsDefaultPrinter -and $settings.PrinterName) { Say $settings.PrinterName }
      exit 0
    }

    'print' {
      if (-not $Job -or -not (Test-Path -LiteralPath $Job)) { Say 'no job file'; exit 2 }
      $spec = Get-Content -LiteralPath $Job -Raw -Encoding UTF8 | ConvertFrom-Json
      $layout = $spec.layout

      $doc = New-Object System.Drawing.Printing.PrintDocument
      $doc.PrintController = New-Object System.Drawing.Printing.StandardPrintController
      $doc.DocumentName = [string]$spec.title
      $doc.PrinterSettings.PrinterName = [string]$spec.printer
      if (-not $doc.PrinterSettings.IsValid) { Say ('no printer called ' + $spec.printer); exit 3 }

      $copies = [int]$spec.copies
      if ($copies -lt 1) { $copies = 1 }
      $doc.PrinterSettings.Copies = [int16]$copies
      $doc.PrinterSettings.Collate = $true

      # The paper by its kind (A4 = 9, Letter = 1), as the driver names it;
      # a driver that does not list it gets the size in hundredths of an inch.
      $kind = if ($spec.paper -eq 'letter') { [System.Drawing.Printing.PaperKind]::Letter } else { [System.Drawing.Printing.PaperKind]::A4 }
      $paper = $null
      foreach ($p in $doc.PrinterSettings.PaperSizes) { if ($p.Kind -eq $kind) { $paper = $p; break } }
      if (-not $paper) {
        $paper = if ($spec.paper -eq 'letter') { New-Object System.Drawing.Printing.PaperSize('Letter', 850, 1100) } else { New-Object System.Drawing.Printing.PaperSize('A4', 827, 1169) }
      }
      $doc.DefaultPageSettings.PaperSize = $paper
      $doc.DefaultPageSettings.Landscape = $false

      $script:pageIndex = 0
      $script:pages = @($layout.pages)
      $script:height = [single]$layout.height
      $format = [System.Drawing.StringFormat]::GenericTypographic
      $format.FormatFlags = $format.FormatFlags -bor [System.Drawing.StringFormatFlags]::NoClip

      $doc.add_PrintPage({
        param($sender, $e)
        $g = $e.Graphics
        $g.PageUnit = [System.Drawing.GraphicsUnit]::Point
        $g.TextRenderingHint = [System.Drawing.Text.TextRenderingHint]::AntiAliasGridFit
        $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
        # The origin is the printable area's corner; the job's is the sheet's.
        # Hard margins come in hundredths of an inch, 0.72 points each.
        $g.TranslateTransform(-[single]($e.PageSettings.HardMarginX * 0.72), -[single]($e.PageSettings.HardMarginY * 0.72))

        $H = $script:height
        foreach ($op in @($script:pages[$script:pageIndex])) {
          $gray = 0
          if ($op.gray) { $gray = [double]$op.gray }
          $v = [int][Math]::Round(255 * $gray)
          $color = [System.Drawing.Color]::FromArgb($v, $v, $v)

          switch ($op.op) {
            'text' {
              if (-not $op.text) { break }
              $style = if ($op.font -eq 'bold') { [System.Drawing.FontStyle]::Bold } else { [System.Drawing.FontStyle]::Regular }
              $font = New-Object System.Drawing.Font('Arial', [single]$op.size, $style, [System.Drawing.GraphicsUnit]::Point)
              $family = $font.FontFamily
              $ascent = [single]$op.size * $family.GetCellAscent($style) / $family.GetEmHeight($style)
              $width = $g.MeasureString([string]$op.text, $font, [System.Drawing.PointF]::Empty, $format).Width
              $shift = 0
              if ($op.align -eq 'right') { $shift = $width } elseif ($op.align -eq 'center') { $shift = $width / 2 }

              $state = $g.Save()
              $g.TranslateTransform([single]$op.x, [single]($H - [double]$op.y))
              if ([int]$op.rotate -eq 180) { $g.RotateTransform(180) }
              $brush = New-Object System.Drawing.SolidBrush($color)
              $g.DrawString([string]$op.text, $font, $brush, [single](-$shift), [single](-$ascent), $format)
              $brush.Dispose()
              $g.Restore($state)
              $font.Dispose()
            }

            'line' {
              $w = [single][Math]::Max(0.1, [double]$op.width)
              $pen = New-Object System.Drawing.Pen($color, $w)
              if ($op.dash) {
                # The pattern is in pen widths here, in points in the job.
                $pen.DashPattern = [single[]]@(([double]$op.dash[0] / $w), ([double]$op.dash[1] / $w))
              }
              $g.DrawLine($pen, [single]$op.x1, [single]($H - [double]$op.y1), [single]$op.x2, [single]($H - [double]$op.y2))
              $pen.Dispose()
            }

            'rect' {
              $top = [single]($H - [double]$op.y - [double]$op.h)
              if ($null -ne $op.fill) {
                $f = [int][Math]::Round(255 * [double]$op.fill)
                $brush = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb($f, $f, $f))
                $g.FillRectangle($brush, [single]$op.x, $top, [single]$op.w, [single]$op.h)
                $brush.Dispose()
              }
              if ([double]$op.width -gt 0) {
                $pen = New-Object System.Drawing.Pen([System.Drawing.Color]::Black, [single]$op.width)
                $g.DrawRectangle($pen, [single]$op.x, $top, [single]$op.w, [single]$op.h)
                $pen.Dispose()
              }
            }
          }
        }

        $script:pageIndex++
        $e.HasMorePages = $script:pageIndex -lt $script:pages.Count
      })

      $doc.Print()
      $doc.Dispose()
      Say 'ok'
      exit 0
    }
  }
}
catch {
  $words = $_.Exception.Message -replace '[\r\n]+', ' '
  Say $words
  exit 1
}
