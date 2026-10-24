# Independent reference for NextLab's fits: R lm() on per-setting means of the fastR2
# Pendulum snapshot (equal weight per distinct length). Regenerate with:
#   Rscript --vanilla backend/test/fixtures/r_reference_fits.R data/pendulum/fastR2_Pendulum_source.csv backend/test/fixtures/r_reference_fits.csv
args <- commandArgs(TRUE)
d <- read.csv(args[1])
m <- aggregate(period ~ length, data = d, FUN = mean)
out <- NULL
for (scenario in c("initial3", "all9")) {
  s <- if (scenario == "initial3") m[order(m$length)[1:3], ] else m
  fams <- list(linear = s$length, sqrt = sqrt(s$length), restricted_quadratic = s$length^2)
  for (f in names(fams)) {
    fit <- lm(s$period ~ fams[[f]])
    out <- rbind(out, data.frame(scenario = scenario, family = f,
                                 a = unname(coef(fit)[2]), b = unname(coef(fit)[1])))
  }
}
write.csv(out, args[2], row.names = FALSE, quote = FALSE)
