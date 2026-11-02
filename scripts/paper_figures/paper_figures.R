# Manuscript figures
#
# Builds the figures for the manuscript from the saved analysis datasets
# and fitted models. Nothing is refit, and no analysis script is changed.
#   Figure 1: distributions of next-night sleep and daily TV, by sample
#   Figure 2: participant-specific residual sleep SDs (Model 1b)
#   Figure 3: within- and between-person TV coefficients (Model 2b)
#   Figure 4: cross-wave stability correlations (Model 3b)
#
# Before running:
#   1. Knit the three *_data_structuring.Rmd scripts (analysis datasets).
#   2. Knit the three *_modeling_fulltime_standard.Rmd scripts (Model 1b
#      and 2b fits in model_fits_m2/, model_fits_mr/, model_fits_m3/).
#   3. Knit cross_wave/Model3_stability_m2_m3.Rmd (Model 3b fit in
#      cross_wave/model_fits_cross_wave/).
#
# How to run (paths are relative to this folder):
#   Terminal:  cd scripts/paper_figures && Rscript paper_figures.R
#              Only some figures: Rscript paper_figures.R 3 4
#   RStudio:   Session > Set Working Directory > To Source File Location,
#              set figures_to_make in Settings, then Source.
#
# Output goes to figures/: a PDF and a 300-dpi PNG per figure, package
# versions (session_info.txt), values flagged for review
# (figure1_flagged_values.csv; contains participant IDs, so it is not
# shared), and cached posterior summaries (cache/). Figures not selected
# are left untouched.
#
# To add a figure: write a make_figureN() function below the existing
# ones, add a fig_sizes entry, then call it and save_figure() in the
# "Run" section.

required_packages <- c("dplyr", "tidyr", "ggplot2", "patchwork", "brms",
                       "posterior", "ragg", "scales")
not_installed <- required_packages[!sapply(required_packages, requireNamespace,
                                           quietly = TRUE)]
if (length(not_installed) > 0) {
  stop("Install these packages first: ", paste(not_installed, collapse = ", "),
       call. = FALSE)
}

suppressPackageStartupMessages({
  library(dplyr)
  library(tidyr)
  library(ggplot2)
  library(patchwork)
})

# ---- Settings ---------------------------------------------------------

# Figures to build (numbers given on the command line override this)
figures_to_make <- 1:4
cli_figures <- suppressWarnings(as.integer(commandArgs(trailingOnly = TRUE)))
if (length(cli_figures) > 0 && !anyNA(cli_figures)) {
  figures_to_make <- cli_figures
}

# Samples, in display order
sample_labels <- c(
  m2 = "MIDUS 2",
  mr = "MIDUS Refresher 1",
  m3 = "MIDUS 3"
)

data_paths <- c(
  m2 = "../midus_2/M2_analysis_data_fulltime_standard.rds",
  mr = "../midus_refresher/MR_analysis_data_fulltime_standard.rds",
  m3 = "../midus_3/M3_analysis_data_fulltime_standard.rds"
)

fit_paths <- c(
  m2 = "../midus_2/model_fits_m2/fulltime_standard/model_1b_fulltime_standard_m2.rds",
  mr = "../midus_refresher/model_fits_mr/fulltime_standard/model_1b_fulltime_standard_mr.rds",
  m3 = "../midus_3/model_fits_m3/fulltime_standard/model_1b_fulltime_standard_m3.rds"
)

# Model 2b: raw-minute TV model (not the log-TV or mi() sensitivity fits)
model_2b_paths <- c(
  m2 = "../midus_2/model_fits_m2/fulltime_standard/model_2b_fulltime_standard_m2.rds",
  mr = "../midus_refresher/model_fits_mr/fulltime_standard/model_2b_fulltime_standard_mr.rds",
  m3 = "../midus_3/model_fits_m3/fulltime_standard/model_2b_fulltime_standard_m3.rds"
)

# Model 3b: joint MIDUS 2 / MIDUS 3 model with correlated random scales
model_3b_path <- "../cross_wave/model_fits_cross_wave/model_3b_stability_m2_m3.rds"

out_dir <- "figures"
cache_dir <- file.path(out_dir, "cache")

# ColorBrewer PuOr (11-class). MIDUS 2 and MIDUS 3 are the same cohort
# (two purples); the Refresher is a different cohort (orange).
sample_colors <- c(
  "MIDUS 2" = "#542788",
  "MIDUS Refresher 1" = "#e08214",
  "MIDUS 3" = "#8073ac"
)
median_color <- "#2d004b"

# Expected counts from the knitted modeling scripts, used as checks
expected <- tibble(
  sample = unname(sample_labels),
  sleep_reports = c(4376, 2139, 1904),
  tv_reports = c(4418, 2140, 1913),
  participants = c(656, 320, 279),
  # Model 2b: complete TV-sleep day-pairs, and the TV coefficients
  # (minutes of sleep per minute of TV) printed in the knitted HTML
  # (rounded to 2 decimals), for validation only
  tv_sleep_pairs = c(4229, 2113, 1869),
  html_tv_within = c(-0.02, -0.01, -0.00),
  html_tv_person_mean = c(0.01, 0.03, 0.02)
)

# Model 3b correlations printed in the knitted HTML, for validation only
expected_3b <- tibble(
  parameter = c(
    "cor_id__waveMIDUS2__waveMIDUS3",
    "cor_id__sigma_waveMIDUS2__sigma_waveMIDUS3"
  ),
  mean = c(0.71, 0.25),
  lower = c(0.60, 0.07),
  upper = c(0.80, 0.41)
)
expected_3b_obs <- 2283
expected_3b_participants <- 169

# Figure 4 outcome colors (ColorBrewer PuOr; outcomes, not samples)
outcome_fill <- c(
  "Average sleep duration" = "#fdb863",
  "Day-to-day sleep variability" = "#b2abd2"
)
outcome_line <- c(
  "Average sleep duration" = "#7f3b08",
  "Day-to-day sleep variability" = "#2d004b"
)

bin_width_hours <- 0.5

# Values outside these bounds are listed for review, never removed
flag_sleep_hours <- c(low = 3, high = 12)
flag_tv_hours_high <- 8

fig_sizes <- list(
  figure1 = c(width = 7, height = 7.5),
  figure2 = c(width = 7, height = 8),
  figure3 = c(width = 7, height = 2.8),
  figure4 = c(width = 7, height = 3.4)
)
png_dpi <- 300
base_font_size <- 10

# ---- Shared helpers ---------------------------------------------------

theme_manuscript <- function() {
  theme_classic(base_size = base_font_size) +
    theme(
      plot.background = element_rect(fill = "white", color = NA),
      panel.background = element_rect(fill = "white", color = NA),
      strip.background = element_rect(fill = "grey95", color = NA),
      strip.text = element_text(face = "bold", size = base_font_size),
      strip.text.y = element_text(angle = -90),
      axis.title = element_text(size = base_font_size),
      plot.title = element_text(face = "bold", size = base_font_size + 1),
      legend.position = "none"
    )
}

check_equal <- function(observed, expected, what) {
  if (!isTRUE(all.equal(as.numeric(observed), as.numeric(expected)))) {
    warning(
      what, ": observed ", paste(observed, collapse = ", "),
      " but expected ", paste(expected, collapse = ", "),
      ". Check the data before using the figure.",
      call. = FALSE
    )
    return(FALSE)
  }
  TRUE
}

# Loads each sample's analysis dataset and drops diary days with no
# recorded weekday (weekend missing), as the modeling scripts do
load_samples <- function() {
  required <- c("id", "weekend", "sleep_next_night_minutes", "tv_duration_minutes")

  lapply(names(data_paths), function(key) {
    path <- data_paths[[key]]
    if (!file.exists(path)) {
      stop("Analysis dataset not found: ", path,
           "\nKnit the data structuring scripts first.", call. = FALSE)
    }
    data <- readRDS(path)
    missing <- setdiff(required, names(data))
    if (length(missing) > 0) {
      stop(path, " is missing columns: ", paste(missing, collapse = ", "),
           call. = FALSE)
    }
    kept <- filter(data, !is.na(weekend))
    message(sprintf(
      "%s: %d diary days (%d dropped for missing weekday); %d sleep and %d TV reports before the drop",
      sample_labels[[key]], nrow(kept), nrow(data) - nrow(kept),
      sum(!is.na(data$sleep_next_night_minutes)),
      sum(!is.na(data$tv_duration_minutes))
    ))
    mutate(kept, sample = sample_labels[[key]])
  }) %>%
    bind_rows() %>%
    mutate(sample = factor(sample, levels = sample_labels))
}

save_figure <- function(plot, name, size) {
  dir.create(out_dir, showWarnings = FALSE, recursive = TRUE)
  pdf_path <- file.path(out_dir, paste0(name, ".pdf"))
  png_path <- file.path(out_dir, paste0(name, ".png"))
  ggsave(pdf_path, plot, width = size[["width"]], height = size[["height"]],
         units = "in", device = pdf_device())
  ggsave(png_path, plot, width = size[["width"]], height = size[["height"]],
         units = "in", dpi = png_dpi, device = ragg::agg_png, bg = "white")
  message("Saved ", pdf_path, " and ", png_path)
}

# Vector PDF: cairo_pdf if it actually opens (capabilities() can report
# Cairo even when its library fails to load, e.g. a Mac without
# XQuartz); otherwise the base pdf device with an encoding that includes
# the en dash
pdf_device <- function() {
  test_file <- tempfile(fileext = ".pdf")
  cairo_works <- tryCatch(
    {
      suppressWarnings(grDevices::cairo_pdf(test_file))
      grDevices::dev.off()
      file.exists(test_file) && file.size(test_file) > 0
    },
    error = function(e) FALSE
  )
  if (cairo_works) {
    return(grDevices::cairo_pdf)
  }
  function(filename, ...) grDevices::pdf(filename, ..., encoding = "WinAnsi")
}

fmt_hours <- function(x) formatC(x, format = "f", digits = 1)

# Correlations as ".71" / "-.05"
fmt_r <- function(x) sub("^(-?)0\\.", "\\1.", sprintf("%.2f", x))

fit_formula_text <- function(fit) {
  # deparse() can split a long formula over several strings
  one_line <- function(f) paste(deparse(f, width.cutoff = 500L), collapse = " ")
  text <- paste(one_line(fit$formula$formula), "|", one_line(fit$formula$pforms$sigma))
  gsub("\\s+", " ", text)
}

fit_signature <- function(path, fit) {
  info <- file.info(path)
  list(
    path = normalizePath(path),
    size = unname(info$size),
    mtime = as.numeric(info$mtime),
    md5 = unname(tools::md5sum(path)),
    nobs = nobs(fit),
    ndraws = posterior::ndraws(fit),
    participants = length(unique(fit$data$id))
  )
}

# Returns compute(fit) for the fit at `path`, reusing the cached result
# only if the fit file is unchanged (path, size, mtime, md5). check(fit)
# validates the fit before anything is computed from it.
cached_from_fit <- function(path, cache_name, label, check, compute) {
  if (!file.exists(path)) {
    stop("Fitted model not found: ", path,
         "\nKnit the script that fits this model first.", call. = FALSE)
  }
  cache_path <- file.path(cache_dir, paste0(cache_name, ".rds"))

  if (file.exists(cache_path)) {
    cached <- readRDS(cache_path)
    info <- file.info(path)
    if (!is.null(cached$result) &&
        identical(cached$signature$path, normalizePath(path)) &&
        identical(cached$signature$size, unname(info$size)) &&
        identical(cached$signature$mtime, as.numeric(info$mtime)) &&
        identical(cached$signature$md5, unname(tools::md5sum(path)))) {
      message(label, ": using cached results")
      return(cached$result)
    }
    message(label, ": fit file changed; recomputing")
  }

  message(label, ": loading ", path)
  fit <- readRDS(path)
  check(fit)
  result <- compute(fit)

  dir.create(cache_dir, showWarnings = FALSE, recursive = TRUE)
  saveRDS(list(signature = fit_signature(path, fit), result = result), cache_path)
  rm(fit)
  gc(verbose = FALSE)
  result
}

# ---- Figure 1: sleep and TV distributions -----------------------------

# One row per available report of each variable (each variable uses all
# of its own reports, not only complete TV-sleep pairs), in hours
figure1_reports <- function(samples) {
  samples %>%
    select(sample, id, sleep_next_night_minutes, tv_duration_minutes) %>%
    pivot_longer(
      c(sleep_next_night_minutes, tv_duration_minutes),
      names_to = "variable", values_to = "minutes"
    ) %>%
    filter(!is.na(minutes)) %>%
    mutate(
      variable = recode(
        variable,
        sleep_next_night_minutes = "sleep",
        tv_duration_minutes = "tv"
      ),
      hours = minutes / 60
    )
}

# Histogram counts as percentages of each panel's available reports.
# Bins are [a, a + width), starting at 0, so zeros fall in the first bin.
bin_reports <- function(reports, x_max) {
  breaks <- seq(0, x_max, by = bin_width_hours)
  reports %>%
    mutate(bin = cut(hours, breaks, right = FALSE, labels = FALSE)) %>%
    count(sample, bin, .drop = FALSE) %>%
    group_by(sample) %>%
    mutate(percent = n / sum(n) * 100) %>%
    ungroup() %>%
    mutate(left = breaks[bin], right = breaks[bin + 1])
}

make_figure1 <- function(samples) {
  reports <- figure1_reports(samples)

  # Checks: available reports per sample and variable
  counts <- reports %>%
    count(sample, variable) %>%
    pivot_wider(names_from = variable, values_from = n) %>%
    arrange(sample)
  print(as.data.frame(counts))
  check_equal(counts$sleep, expected$sleep_reports, "Sleep reports")
  check_equal(counts$tv, expected$tv_reports, "TV reports")

  # Values for review (kept in the figure)
  flagged <- reports %>%
    filter(
      (variable == "sleep" &
        (hours < flag_sleep_hours[["low"]] | hours > flag_sleep_hours[["high"]])) |
        (variable == "tv" & hours > flag_tv_hours_high)
    ) %>%
    arrange(sample, variable, minutes) %>%
    select(sample, id, variable, minutes)
  dir.create(out_dir, showWarnings = FALSE, recursive = TRUE)
  write.csv(flagged, file.path(out_dir, "figure1_flagged_values.csv"), row.names = FALSE)
  message("Values flagged for review (kept in the figure):")
  print(as.data.frame(count(flagged, sample, variable)))

  variables <- list(
    sleep = list(title = "Next-night sleep", x_title = "Sleep duration (hours)"),
    tv = list(title = "Daily TV viewing", x_title = "TV viewing (hours)")
  )

  # Full observed range, rounded up to a whole bin (a value exactly on
  # the top boundary gets its own bin)
  x_max <- sapply(names(variables), function(v) {
    top <- max(reports$hours[reports$variable == v])
    (floor(top / bin_width_hours) + 1) * bin_width_hours
  })

  bins <- lapply(names(variables), function(v) {
    bin_reports(filter(reports, variable == v), x_max[[v]])
  })
  names(bins) <- names(variables)

  # One percentage scale for all six panels
  y_max <- max(sapply(bins, function(b) max(b$percent)))
  y_max <- ceiling(y_max / 5) * 5

  stats <- reports %>%
    group_by(sample, variable) %>%
    summarise(
      n = n(),
      median = median(hours),
      q1 = quantile(hours, 0.25),
      q3 = quantile(hours, 0.75),
      min = min(hours),
      max = max(hours),
      .groups = "drop"
    ) %>%
    mutate(label = sprintf(
      "n = %s\nMdn = %s h\nIQR %s–%s h\nRange %s–%s h",
      format(n, big.mark = ","), fmt_hours(median), fmt_hours(q1), fmt_hours(q3),
      fmt_hours(min), fmt_hours(max)
    ))

  panels <- lapply(names(variables), function(v) {
    v_stats <- filter(stats, variable == v)
    ggplot(bins[[v]]) +
      geom_rect(
        aes(xmin = left, xmax = right, ymin = 0, ymax = percent, fill = sample),
        color = "white", linewidth = 0.15
      ) +
      # White underlay keeps the dashed median visible over dark bars
      geom_vline(
        data = v_stats, aes(xintercept = median),
        color = "white", linewidth = 1.3
      ) +
      geom_vline(
        data = v_stats, aes(xintercept = median),
        color = median_color, linetype = "dashed", linewidth = 0.6
      ) +
      geom_text(
        data = v_stats, aes(label = label),
        x = x_max[[v]], y = y_max, hjust = 1, vjust = 1,
        size = (base_font_size - 2) / .pt, lineheight = 0.95
      ) +
      facet_grid(sample ~ .) +
      scale_fill_manual(values = sample_colors) +
      scale_x_continuous(
        limits = c(0, x_max[[v]]), breaks = seq(0, x_max[[v]], by = 2),
        expand = expansion(mult = c(0.01, 0.01))
      ) +
      scale_y_continuous(
        limits = c(0, y_max), expand = expansion(mult = c(0, 0.02))
      ) +
      labs(title = variables[[v]]$title, x = variables[[v]]$x_title,
           y = "Percentage of reports") +
      theme_manuscript()
  })

  # Sample labels only on the right-hand column; y title only on the left
  panels[[1]] <- panels[[1]] + theme(strip.text.y = element_blank())
  panels[[2]] <- panels[[2]] + theme(axis.title.y = element_blank())

  list(
    plot = panels[[1]] + panels[[2]] + plot_layout(ncol = 2),
    stats = stats,
    y_max = y_max,
    x_max = x_max,
    n_flagged = nrow(flagged)
  )
}

# ---- Figure 2: participant-specific residual sleep SDs ----------------

check_model_1b <- function(fit, key) {
  label <- sample_labels[[key]]
  if (!inherits(fit, "brmsfit")) {
    stop(fit_paths[[key]], " is not a brmsfit.", call. = FALSE)
  }
  formula_text <- fit_formula_text(fit)
  wanted <- c(
    "sleep_next_night_minutes ~ 1 + weekend + (1 | q | id)",
    "sigma ~ 1 + (1 | q | id)"
  )
  if (!all(sapply(wanted, grepl, x = formula_text, fixed = TRUE))) {
    stop(label, ": ", fit_paths[[key]], " is not Model 1b. Formula: ",
         formula_text, call. = FALSE)
  }
  exp_row <- expected[expected$sample == label, ]
  n_ids <- length(unique(fit$data$id))
  ok <- c(
    check_equal(n_ids, exp_row$participants, paste(label, "Model 1b participants")),
    check_equal(nobs(fit), exp_row$sleep_reports, paste(label, "Model 1b observations"))
  )
  if (!all(ok)) {
    stop(label, ": the Model 1b fit does not match the current analysis ",
         "sample (stale fit?). See warnings above.", call. = FALSE)
  }
}

# Posterior draws of each participant's residual SD in minutes:
# exp(b_sigma_Intercept + r_id__sigma[id, Intercept]), computed for every
# draw before summarising
sigma_draws <- function(fit) {
  draws <- posterior::as_draws_matrix(
    fit,
    variable = c("^b_sigma_Intercept$", "^r_id__sigma\\["),
    regex = TRUE
  )
  intercept <- as.numeric(draws[, "b_sigma_Intercept"])
  re_cols <- grep("^r_id__sigma\\[", colnames(draws), value = TRUE)
  log_sd <- unclass(draws[, re_cols]) + intercept
  sd_draws <- exp(log_sd)
  colnames(sd_draws) <- sub("^r_id__sigma\\[(.*),Intercept\\]$", "\\1", re_cols)
  sd_draws
}

summarise_sigma <- function(key) {
  cached_from_fit(
    fit_paths[[key]],
    cache_name = paste0("fig2_sigma_", key),
    label = paste(sample_labels[[key]], "Model 1b"),
    check = function(fit) check_model_1b(fit, key),
    compute = function(fit) {
      sd_draws <- sigma_draws(fit)

      # Cross-check a few participants against brms's own sigma predictions
      check_ids <- head(colnames(sd_draws), 5)
      newdata <- data.frame(
        id = fit$data$id[match(check_ids, as.character(fit$data$id))],
        weekend = 0
      )
      brms_sd <- brms::posterior_linpred(
        fit, newdata = newdata, dpar = "sigma", transform = TRUE
      )
      if (max(abs(brms_sd - sd_draws[, check_ids])) > 1e-8) {
        stop(sample_labels[[key]], ": residual SD draws do not match ",
             "posterior_linpred(dpar = \"sigma\").", call. = FALSE)
      }

      tibble(
        id = colnames(sd_draws),
        mean = colMeans(sd_draws),
        lower = apply(sd_draws, 2, quantile, probs = 0.05),
        upper = apply(sd_draws, 2, quantile, probs = 0.95),
        sample = sample_labels[[key]]
      )
    }
  )
}

make_figure2 <- function() {
  summaries <- lapply(names(fit_paths), summarise_sigma) %>%
    bind_rows() %>%
    mutate(sample = factor(sample, levels = sample_labels)) %>%
    group_by(sample) %>%
    arrange(mean, .by_group = TRUE) %>%
    mutate(rank = row_number()) %>%
    ungroup()

  check_equal(
    as.numeric(table(summaries$sample)), expected$participants,
    "Figure 2 participants"
  )

  plot <- ggplot(summaries, aes(x = rank, y = mean, color = sample)) +
    geom_linerange(aes(ymin = lower, ymax = upper), linewidth = 0.3, alpha = 0.3) +
    geom_point(size = 0.5) +
    facet_wrap(~sample, ncol = 1, scales = "free_x", strip.position = "top") +
    scale_color_manual(values = sample_colors) +
    scale_x_continuous(expand = expansion(mult = 0.01)) +
    scale_y_continuous(limits = c(0, NA), expand = expansion(mult = c(0, 0.03))) +
    labs(
      x = "Participant rank (by posterior mean day-to-day sleep variability, within sample)",
      y = "Day-to-day sleep variability\n(residual SD, minutes)"
    ) +
    theme_manuscript() +
    theme(strip.text = element_text(hjust = 0))

  list(plot = plot, summaries = summaries)
}

# ---- Figure 3: within- and between-person TV coefficients -------------

check_model_2b <- function(fit, key) {
  label <- sample_labels[[key]]
  if (!inherits(fit, "brmsfit")) {
    stop(model_2b_paths[[key]], " is not a brmsfit.", call. = FALSE)
  }
  formula_text <- fit_formula_text(fit)
  wanted <- c(
    "sleep_next_night_minutes ~ 1 + weekend + age_centered + sex + tv_within + tv_person_mean + (1 | q | id)",
    "sigma ~ 1 + (1 | q | id)"
  )
  if (!all(sapply(wanted, grepl, x = formula_text, fixed = TRUE)) ||
      grepl("mi(", formula_text, fixed = TRUE) ||
      grepl("log", formula_text, fixed = TRUE)) {
    stop(label, ": ", model_2b_paths[[key]], " is not the raw-minute ",
         "Model 2b. Formula: ", formula_text, call. = FALSE)
  }
  missing <- setdiff(c("b_tv_within", "b_tv_person_mean"), posterior::variables(fit))
  if (length(missing) > 0) {
    stop(label, ": Model 2b has no parameter ", paste(missing, collapse = ", "),
         call. = FALSE)
  }
  exp_row <- expected[expected$sample == label, ]
  ok <- c(
    check_equal(nobs(fit), exp_row$tv_sleep_pairs, paste(label, "Model 2b observations")),
    check_equal(length(unique(fit$data$id)), exp_row$participants,
                paste(label, "Model 2b participants"))
  )
  if (!all(ok)) {
    stop(label, ": the Model 2b fit does not match the current analysis ",
         "sample (stale fit?). See warnings above.", call. = FALSE)
  }
}

# Draws of the two TV coefficients in minutes of sleep per hour of TV:
# each draw (minutes per minute) times 60, before summarising
tv_coefficient_draws <- function(key) {
  cached_from_fit(
    model_2b_paths[[key]],
    cache_name = paste0("fig3_model_2b_", key),
    label = paste(sample_labels[[key]], "Model 2b"),
    check = function(fit) check_model_2b(fit, key),
    compute = function(fit) {
      draws <- posterior::as_draws_df(fit, variable = c("b_tv_within", "b_tv_person_mean"))
      tibble(
        within = 60 * draws$b_tv_within,
        between = 60 * draws$b_tv_person_mean,
        raw_within = draws$b_tv_within,
        raw_between = draws$b_tv_person_mean
      )
    }
  )
}

make_figure3 <- function() {
  draws <- lapply(names(model_2b_paths), function(key) {
    mutate(tv_coefficient_draws(key), sample = sample_labels[[key]])
  }) %>%
    bind_rows()

  summaries <- draws %>%
    pivot_longer(c(within, between), names_to = "effect", values_to = "value") %>%
    group_by(sample, effect) %>%
    summarise(
      draws = n(),
      mean = mean(value),
      lower = quantile(value, 0.05),
      upper = quantile(value, 0.95),
      .groups = "drop"
    ) %>%
    mutate(sample = factor(sample, levels = rev(sample_labels)))

  # Validation: raw (per-minute) posterior means against the HTML values
  raw_means <- draws %>%
    group_by(sample) %>%
    summarise(within = mean(raw_within), between = mean(raw_between)) %>%
    slice(match(expected$sample, sample))
  for (effect in c("within", "between")) {
    html <- if (effect == "within") expected$html_tv_within else expected$html_tv_person_mean
    off <- abs(raw_means[[effect]] - html) > 0.0051
    if (any(off)) {
      warning("Model 2b ", effect, " means differ from the knitted HTML for ",
              paste(raw_means$sample[off], collapse = ", "), call. = FALSE)
    }
  }

  # One axis for both panels, wide enough for every interval and zero
  limits <- range(c(0, summaries$lower, summaries$upper))
  limits <- c(floor(limits[1]) - 0.5, ceiling(limits[2]) + 0.5)

  panels <- list(
    within = list(title = "A  Within person",
                  subtitle = "1 h more TV than the participant's own average"),
    between = list(title = "B  Between person",
                   subtitle = "1 h more in the participant's average daily TV")
  )

  plots <- lapply(names(panels), function(effect) {
    ggplot(filter(summaries, effect == !!effect),
           aes(x = mean, y = sample, color = sample)) +
      geom_vline(xintercept = 0, linetype = "dashed", color = "grey45", linewidth = 0.4) +
      geom_linerange(aes(xmin = lower, xmax = upper), linewidth = 0.9) +
      geom_point(size = 2.4) +
      scale_color_manual(values = sample_colors) +
      scale_x_continuous(limits = limits, breaks = scales::breaks_pretty(n = 6)) +
      labs(
        title = panels[[effect]]$title,
        subtitle = panels[[effect]]$subtitle,
        x = "Sleep (minutes per hour of TV)",
        y = NULL
      ) +
      theme_manuscript() +
      theme(
        plot.subtitle = element_text(size = base_font_size - 1, color = "grey25"),
        axis.text.y = element_text(size = base_font_size, color = "black")
      )
  })
  plots[[2]] <- plots[[2]] + theme(axis.text.y = element_blank())

  list(plot = plots[[1]] + plots[[2]] + plot_layout(ncol = 2), summaries = summaries)
}

# ---- Figure 4: cross-wave stability (Model 3b) -------------------------

check_model_3b <- function(fit) {
  if (!inherits(fit, "brmsfit")) {
    stop(model_3b_path, " is not a brmsfit.", call. = FALSE)
  }
  formula_text <- fit_formula_text(fit)
  wanted <- c(
    "sleep_next_night_minutes ~ 0 + wave + weekend + (0 + wave | c | id)",
    "sigma ~ 0 + wave + (0 + wave | c | id)"
  )
  if (!all(sapply(wanted, grepl, x = formula_text, fixed = TRUE))) {
    stop(model_3b_path, " is not Model 3b (Model 3a uses uncorrelated ",
         "scales). Formula: ", formula_text, call. = FALSE)
  }
  missing <- setdiff(expected_3b$parameter, posterior::variables(fit))
  if (length(missing) > 0) {
    stop("Model 3b has no parameter ", paste(missing, collapse = ", "), call. = FALSE)
  }
  ok <- c(
    check_equal(nobs(fit), expected_3b_obs, "Model 3b observations"),
    check_equal(length(unique(fit$data$id)), expected_3b_participants,
                "Model 3b participants")
  )
  if (!all(ok)) {
    stop("The Model 3b fit does not match the current panel sample.", call. = FALSE)
  }
}

# Density on [-1, 1], reflected at both bounds so no mass falls outside
# the valid correlation range
bounded_density <- function(x, n = 512) {
  bw <- stats::bw.nrd0(x)
  d <- stats::density(c(x, -2 - x, 2 - x), bw = bw, from = -1, to = 1, n = n)
  tibble(r = d$x, density = d$y * 3)
}

make_figure4 <- function() {
  draws <- cached_from_fit(
    model_3b_path,
    cache_name = "fig4_model_3b",
    label = "Model 3b",
    check = check_model_3b,
    compute = function(fit) {
      d <- posterior::as_draws_df(fit, variable = expected_3b$parameter)
      tibble(
        average = d[[expected_3b$parameter[1]]],
        variability = d[[expected_3b$parameter[2]]]
      )
    }
  )

  outcomes <- c(
    average = "Average sleep duration",
    variability = "Day-to-day sleep variability"
  )
  rows <- c(average = 2, variability = 1)

  summaries <- tibble(
    key = names(outcomes),
    outcome = unname(outcomes),
    row = unname(rows),
    n_draws = nrow(draws),
    mean = sapply(names(outcomes), function(k) mean(draws[[k]])),
    lower = sapply(names(outcomes), function(k) quantile(draws[[k]], 0.05)),
    upper = sapply(names(outcomes), function(k) quantile(draws[[k]], 0.95))
  ) %>%
    mutate(label = sprintf("Mean r = %s\n90%% CrI [%s, %s]",
                           fmt_r(mean), fmt_r(lower), fmt_r(upper)))

  # Validation against the knitted HTML
  off <- abs(summaries$mean - expected_3b$mean) > 0.0051 |
    abs(summaries$lower - expected_3b$lower) > 0.0051 |
    abs(summaries$upper - expected_3b$upper) > 0.0051
  if (any(off)) {
    warning("Model 3b correlations differ from the knitted HTML for: ",
            paste(summaries$outcome[off], collapse = ", "), call. = FALSE)
  }
  stopifnot(all(abs(unlist(draws)) <= 1))

  # Each density scaled to the same peak height within its row
  dens <- lapply(names(outcomes), function(k) {
    bounded_density(draws[[k]]) %>%
      mutate(
        outcome = outcomes[[k]],
        ymin = rows[[k]],
        ymax = rows[[k]] + 0.78 * density / max(density)
      )
  }) %>%
    bind_rows()

  plot <- ggplot() +
    geom_vline(xintercept = 0, linetype = "dashed", color = "grey45", linewidth = 0.4) +
    geom_ribbon(
      data = dens,
      aes(x = r, ymin = ymin, ymax = ymax, fill = outcome, color = outcome),
      linewidth = 0.4
    ) +
    geom_segment(
      data = summaries,
      aes(x = lower, xend = upper, y = row - 0.09, yend = row - 0.09, color = outcome),
      linewidth = 1.1
    ) +
    geom_point(
      data = summaries,
      aes(x = mean, y = row - 0.09, color = outcome),
      size = 2.4
    ) +
    geom_text(
      data = summaries,
      aes(x = -0.98, y = row + 0.42, label = label),
      hjust = 0, vjust = 0.5, size = (base_font_size - 1) / .pt, lineheight = 0.95
    ) +
    scale_fill_manual(values = outcome_fill) +
    scale_color_manual(values = outcome_line) +
    scale_x_continuous(
      limits = c(-1, 1), breaks = seq(-1, 1, by = 0.5),
      labels = function(x) ifelse(x %in% c(-1, 0, 1), as.character(x), fmt_r(x)),
      expand = expansion(mult = 0.01)
    ) +
    scale_y_continuous(
      breaks = summaries$row + 0.3, labels = summaries$outcome,
      limits = c(0.8, 2.85), expand = expansion(0)
    ) +
    labs(x = "Correlation between MIDUS 2 and MIDUS 3", y = NULL) +
    theme_manuscript() +
    theme(
      axis.text.y = element_text(size = base_font_size, color = "black"),
      axis.ticks.y = element_blank()
    )

  list(plot = plot, summaries = summaries)
}

# ---- Run --------------------------------------------------------------

message("Building figures: ", paste(figures_to_make, collapse = ", "))

if (1 %in% figures_to_make) {
  samples <- load_samples()
  fig1 <- make_figure1(samples)
  save_figure(fig1$plot, "figure1_distributions", fig_sizes$figure1)
  message("\nFigure 1 summaries (hours):")
  print(as.data.frame(fig1$stats[, c("sample", "variable", "n", "median", "q1", "q3", "min", "max")]))
}

if (2 %in% figures_to_make) {
  fig2 <- make_figure2()
  save_figure(fig2$plot, "figure2_residual_sd", fig_sizes$figure2)
  message("\nFigure 2 residual SD posterior means (minutes):")
  print(as.data.frame(
    fig2$summaries %>%
      group_by(sample) %>%
      summarise(
        participants = n(),
        min = min(mean), median = median(mean), max = max(mean),
        widest_interval = max(upper - lower),
        .groups = "drop"
      )
  ))
}

if (3 %in% figures_to_make) {
  fig3 <- make_figure3()
  save_figure(fig3$plot, "figure3_tv_sleep_associations", fig_sizes$figure3)
  message("\nFigure 3 TV coefficients (minutes of sleep per hour of TV):")
  print(as.data.frame(arrange(fig3$summaries, effect, desc(sample))))
}

if (4 %in% figures_to_make) {
  fig4 <- make_figure4()
  save_figure(fig4$plot, "figure4_cross_wave_stability", fig_sizes$figure4)
  message("\nFigure 4 Model 3b correlations:")
  print(as.data.frame(fig4$summaries[, c("outcome", "n_draws", "mean", "lower", "upper")]))
}

writeLines(capture.output(sessionInfo()), file.path(out_dir, "session_info.txt"))
message("Wrote ", file.path(out_dir, "session_info.txt"))
