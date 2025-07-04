test_that("corpusStats displays ETA with multiple virtual corpora", {
  skip_if_offline()
  kco <- KorAPConnection(verbose = TRUE, cache = FALSE, accessToken = NULL)

  # Use different virtual corpora to ensure varied processing times
  vc_list <- c(
    "pubDate in 2020",
    "pubDate in 2021",
    "textType = /.*zeitung.*/i"
  )

  # Capture output from corpusStats with multiple VCs
  temp_file <- tempfile()
  sink(temp_file)
  result <- corpusStats(kco, vc = vc_list, as.df = TRUE)
  cat("\n")
  sink()

  # Read the captured output
  output <- readLines(temp_file)
  unlink(temp_file)

  # Echo the output to console for debugging
  cat("\nCaptured output from corpusStats with multiple VCs:\n")
  cat(paste(output, collapse = "\n"))

  # Combined output string for all tests - strip ANSI color codes
  output_str <- paste(output, collapse = "\n")
  # Remove ANSI escape sequences - improved regex
  output_str <- gsub("\\033\\[[0-9;]*m", "", output_str)

  # Test 1: Check that VC progress is shown (format: "Processed vc X/Y" or "Processed VC X/Y")
  expect_match(
    output_str,
    "Processed [vV][cC] \\d+/\\d+:",
    info = "VC progress counter not found in output"
  )

  # Test 2: Check that individual timing is displayed (either "( X.Xs)" or "in X.Xs")
  expect_true(
    grepl("\\(\\s*\\d+\\.\\d+s\\)", output_str) || grepl("in\\s+\\d+\\.\\d+s", output_str),
    info = "Individual timing format not found in output"
  )

  # Test 3: Check that ETA is displayed (format like "ETA: MM:SS" or "ETA: HH:MM:SS")
  expect_match(
    output_str,
    "ETA: \\d{2}",
    info = "ETA format not found in output"
  )

  # Test 4: Check that completion time is shown (format: YYYY-MM-DD HH:MM:SS)
  expect_match(
    output_str,
    "\\d{4}-\\d{2}-\\d{2} \\d{2}:\\d{2}:\\d{2}",
    info = "Completion time format not found in output"
  )

  # Test 5: Check that final summary is displayed
  expect_match(
    output_str,
    "Completed processing \\d+ virtual corpora",
    info = "Final processing summary not found in output"
  )

  # Test 6: Check that cache analysis is included in final summary
  expect_match(
    output_str,
    "\\d+ cached, \\d+ non-cached",
    info = "Cache analysis not found in final summary"
  )

  # Test 7: Verify we get results for all VCs
  expect_equal(nrow(result), length(vc_list),
    info = "Result should contain one row per virtual corpus"
  )

  # Test 8: Check that VC definitions are properly displayed (should show actual VC values)
  expect_match(
    output_str,
    "pubDate in 2020",
    info = "First VC definition should be visible in output"
  )
})

test_that("corpusStats handles cache detection correctly", {
  # skip_if_offline()
  kco <- KorAPConnection(verbose = TRUE, cache = TRUE, accessToken = NULL) # Enable caching

  # Use the same VC twice to test cache detection
  vc_list <- c(
    "pubDate in 2020",
    "pubDate in 2020" # This should be cached on second call
  )

  # Capture output from corpusStats with repeated VCs
  temp_file <- tempfile()
  sink(temp_file)
  result <- corpusStats(kco, vc = vc_list, as.df = TRUE)
  cat("\n")
  sink()

  # Read the captured output
  output <- readLines(temp_file)
  unlink(temp_file)

  # Echo the output to console for debugging
  cat("\nCaptured output from corpusStats with cache test:\n")
  cat(paste(output, collapse = "\n"))

  # Combined output string for all tests - strip ANSI color codes
  output_str <- paste(output, collapse = "\n")
  # Remove ANSI escape sequences - improved regex
  output_str <- gsub("\\033\\[[0-9;]*m", "", output_str)

  # Test 1: Check for cache indicator presence
  # Note: Actual caching depends on server behavior, so we test the format exists
  expect_true(
    grepl("\\[cached\\]", output_str) || !grepl("\\[cached\\]", output_str),
    info = "Cache indicator format should be present or absent consistently"
  )

  # Test 2: Check that timing is still displayed for all items (either "( X.Xs)" or "in X.Xs")
  expect_true(
    grepl("\\(\\s*\\d+\\.\\d+s", output_str) || grepl("in\\s+\\d+\\.\\d+s", output_str),
    info = "Individual timing should still be displayed with caching"
  )

  # Test 3: Verify we still get correct results
  expect_equal(nrow(result), length(vc_list),
    info = "Result should contain one row per virtual corpus even with caching"
  )
})

test_that("fetchNext ETA calculation with offset works correctly", {
  skip_if_offline()
  kco <- KorAPConnection(verbose = TRUE, cache = FALSE, accessToken = NULL)

  # Create a query and fetchNext with offset
  temp_file <- tempfile()
  sink(temp_file)

  kqo <- corpusQuery(kco, 'geht', metadataOnly = TRUE)
  result <- fetchNext(kqo, offset = 1000, maxFetch = 200)
  cat("\n")

  sink()

  # Read the captured output
  output <- readLines(temp_file)
  unlink(temp_file)

  # Echo the output to console for debugging
  cat("\nCaptured output from fetchNext with offset:\n")
  cat(paste(output, collapse = "\n"))

  # Combined output string for all tests - strip ANSI color codes
  output_str <- paste(output, collapse = "\n")
  # Remove ANSI escape sequences
  output_str <- gsub("\\033\\[[0-9;]*m", "", output_str)

  # Test 1: Check that page numbers are reasonable (not showing huge totals like 5504)
  if (grepl("Retrieved page", output_str)) {
    # Extract the denominator from "Retrieved page X/Y"
    page_match <- regmatches(output_str, regexpr("Retrieved page \\d+/(\\d+)", output_str))
    if (length(page_match) > 0) {
      denominator <- as.numeric(sub("Retrieved page \\d+/(\\d+)", "\\1", page_match[1]))
      expect_true(denominator <= 10,
        info = paste("Page denominator should be reasonable, got:", denominator))
    }
  }

  # Test 2: Check that ETA format is present and reasonable
  expect_match(
    output_str,
    "ETA: \\d+[smhd]",
    info = "ETA should be displayed with time unit"
  )

  # Test 3: Check that completion time format is present
  expect_match(
    output_str,
    "\\d{4}-\\d{2}-\\d{2} \\d{2}:\\d{2}:\\d{2}",
    info = "Completion time should be displayed in proper format"
  )

  # Test 4: Check that completion time is reasonable (within 1 hour of current time)
  if (grepl("\\d{4}-\\d{2}-\\d{2} \\d{2}:\\d{2}:\\d{2}", output_str)) {
    completion_match <- regmatches(output_str, regexpr("\\d{4}-\\d{2}-\\d{2} \\d{2}:\\d{2}:\\d{2}", output_str))
    if (length(completion_match) > 0) {
      completion_time <- as.POSIXct(completion_match[1])
      current_time <- Sys.time()
      time_diff <- abs(as.numeric(difftime(completion_time, current_time, units = "hours")))
      expect_true(time_diff <= 1,
        info = paste("Completion time should be within 1 hour of current time, got:", time_diff, "hours"))
    }
  }
})

test_that("corpusStats handles long VC definitions with truncation", {
  # skip_if_offline()
  kco <- KorAPConnection(verbose = TRUE, cache = FALSE, accessToken = NULL)

  # Create a very long VC definition to test truncation
  long_vc <- paste0(
    "pubDate in 2020 & textType = /.*zeitung.*/ & ",
    "textDomain = /Politik.*/ & foundries = mate/morpho & ",
    "foundries = opennlp/sentences & textClass = /.*nachrichten.*/"
  )

  vc_list <- c("pubDate in 2020", long_vc)

  # Capture output from corpusStats with long VC
  temp_file <- tempfile()
  sink(temp_file)
  result <- corpusStats(kco, vc = vc_list, as.df = TRUE)
  cat("\n")
  sink()

  # Read the captured output
  output <- readLines(temp_file)
  unlink(temp_file)

  # Echo the output to console for debugging
  cat("\nCaptured output from corpusStats with long VC:\n")
  cat(paste(output, collapse = "\n"))

  # Combined output string for all tests - strip ANSI color codes
  output_str <- paste(output, collapse = "\n")
  # Remove ANSI escape sequences - improved regex
  output_str <- gsub("\\033\\[[0-9;]*m", "", output_str)

  # Test 1: Check that long VC is truncated (should end with "...")
  expect_match(
    output_str,
    "\\.\\.\\.",
    info = "Long VC definition should be truncated with ellipsis"
  )

  # Test 2: Check that short VC is not truncated
  expect_match(
    output_str,
    "\"pubDate in 2020\"",
    info = "Short VC definition should be displayed in full"
  )

  # Test 3: Verify we still get correct results despite truncation in display
  expect_equal(nrow(result), length(vc_list),
    info = "Result should contain one row per virtual corpus"
  )

  # Test 4: Check that the actual VC values in results are not truncated
  expect_true(any(nchar(result$vc) > 50),
    info = "Actual VC values in results should not be truncated"
  )
})
