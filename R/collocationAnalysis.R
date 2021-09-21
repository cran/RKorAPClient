setGeneric("collocationAnalysis", function(kco, ...)  standardGeneric("collocationAnalysis") )

#' Collocation analysis
#'
#' @aliases collocationAnalysis
#'
#' @description
#' `r lifecycle::badge("experimental")`
#'
#' Performs a collocation analysis for the given node (or query)
#' in the given virtual corpus.
#'
#' @details
#' The collocation analysis is currently implemented on the client side, as some of the
#' functionality is not yet provided by the KorAP backend. Mainly for this reason
#' it is very slow (several minutes, up to hours), but on the other hand very flexible.
#' You can, for example, perform the analysis in arbitrary virtual corpora, use complex node queries,
#' and look for expression-internal collocates using the focus function (see examples and demo).
#'
#' To increase speed at the cost of accuracy and possible false negatives,
#' you can decrease searchHitsSampleLimit and/or topCollocatesLimit and/or set exactFrequencies to FALSE.
#'
#' Note that currently not the tokenization provided by the backend, i.e. the corpus itself, is used, but a tinkered one.
#' This can also lead to false negatives and to frequencies that differ from corresponding ones acquired via the web
#' user interface.
#'
#' @family collocation analysis functions
#'
#' @param lemmatizeNodeQuery     if TRUE, node query will be lemmatized, i.e. `x -> [tt/l=x]`
#' @param minOccur               minimum absolute number of observed co-occurrences to consider a collocate candidate
#' @param topCollocatesLimit     limit analysis to the n most frequent collocates in the search hits sample
#' @param searchHitsSampleLimit  limit the size of the search hits sample
#' @param stopwords              vector of stopwords not to be considered as collocates
#' @param exactFrequencies       if FALSE, extrapolate observed co-occurrence frequencies from frequencies in search hits sample, otherwise retrieve exact co-occurrence frequencies
#' @param seed                   seed for random page collecting order
#' @param expand                 if TRUE, `node` and `vc` parameters are expanded to all of their combinations
#' @param ...                    more arguments will be passed to [collocationScoreQuery()]
#' @inheritParams collocationScoreQuery,KorAPConnection-method
#' @return Tibble with top collocates, association scores, corresponding URLs for web user interface queries, etc.
#'
#' @importFrom stringr str_match str_split str_detect
#' @importFrom dplyr anti_join arrange desc slice_head bind_rows
#' @importFrom purrr pmap
#' @importFrom tidyr expand_grid
#'
#' @examples
#' \dontrun{
#'
#'  # Find top collocates of "Packung" inside and outside the sports domain.
#'  new("KorAPConnection", verbose = TRUE) %>%
#'   collocationAnalysis("Packung", vc=c("textClass=sport", "textClass!=sport"),
#'                       leftContextSize=1, rightContextSize=1, topCollocatesLimit=20) %>%
#'   dplyr::filter(logDice >= 5)
#' }
#'
#' \dontrun{
#'
#' # Identify the most prominent light verb construction with "in ... setzen".
#' # Note that, currently, the use of focus function disallows exactFrequencies.
#' new("KorAPConnection", verbose = TRUE) %>%
#'   collocationAnalysis("focus(in [tt/p=NN] {[tt/l=setzen]})",
#'     leftContextSize=1, rightContextSize=0, exactFrequencies=FALSE, topCollocatesLimit=20)
#' }
#'
#' @export
setMethod("collocationAnalysis", "KorAPConnection",
          function(kco,
                   node,
                   vc = "",
                   lemmatizeNodeQuery = FALSE,
                   minOccur = 5,
                   leftContextSize = 5,
                   rightContextSize = 5,
                   topCollocatesLimit = 200,
                   searchHitsSampleLimit = 20000,
                   ignoreCollocateCase = FALSE,
                   withinSpan = ifelse(exactFrequencies, "base/s=s", ""),
                   exactFrequencies = TRUE,
                   stopwords = RKorAPClient::synsemanticStopwords(),
                   seed = 7,
                   expand = length(vc) != length(node),
                   ...) {
            # https://stackoverflow.com/questions/8096313/no-visible-binding-for-global-variable-note-in-r-cmd-check
            word <- frequency <- NULL

            if(!exactFrequencies && (!is.na(withinSpan) && !is.null(withinSpan) && nchar(withinSpan)>0 )) {
              stop(sprintf("Not empty withinSpan (='%s') requires exactFrequencies=TRUE", withinSpan), call. = FALSE)
            }

            warnIfNoAccessToken(kco)

            if (lemmatizeNodeQuery) {
              node <- lemmatizeWordQuery(node)
            }

            if (length(node) > 1 || length(vc) > 1) {
              grid <- if (expand) expand_grid(node=node, vc=vc) else tibble(node=node, vc=vc)
              purrr::pmap(grid, function(node, vc, ...)
                        collocationAnalysis(kco,
                                            node =node,
                                            vc = vc,
                                            minOccur = minOccur,
                                            leftContextSize = leftContextSize,
                                            rightContextSize = rightContextSize,
                                            topCollocatesLimit = topCollocatesLimit,
                                            searchHitsSampleLimit = searchHitsSampleLimit,
                                            ignoreCollocateCase = ignoreCollocateCase,
                                            withinSpan = withinSpan,
                                            exactFrequencies = exactFrequencies,
                                            stopwords = stopwords,
                                            seed = seed,
                                            expand = expand,
                                            ...) ) %>%
                bind_rows()
            } else {
              set.seed(seed)
              candidates <- collocatesQuery(
                kco,
                node,
                vc = vc,
                minOccur = minOccur,
                leftContextSize = leftContextSize,
                rightContextSize = rightContextSize,
                searchHitsSampleLimit = searchHitsSampleLimit,
                ignoreCollocateCase = ignoreCollocateCase,
                stopwords = stopwords,
                ...
              )

              if (nrow(candidates) > 0) {
                candidates <- candidates %>%
                  filter(frequency >= minOccur) %>%
                  head(topCollocatesLimit)
                collocationScoreQuery(
                  kco,
                  node = node,
                  collocate = candidates$word,
                  vc = vc,
                  leftContextSize = leftContextSize,
                  rightContextSize = rightContextSize,
                  observed = if (exactFrequencies) NA else candidates$frequency,
                  ignoreCollocateCase = ignoreCollocateCase,
                  withinSpan = withinSpan,
                  ...
                ) %>%
                  filter(.$O >= minOccur) %>%
                  dplyr::arrange(dplyr::desc(logDice))
              } else {
                tibble()
              }
            }
          }
)

#' @importFrom magrittr debug_pipe
#' @importFrom stringr str_match str_split str_detect
#' @importFrom dplyr as_tibble tibble rename filter anti_join tibble bind_rows case_when
#'
snippet2FreqTable <- function(snippet,
                              minOccur = 5,
                              leftContextSize = 5,
                              rightContextSize = 5,
                              ignoreCollocateCase = FALSE,
                              stopwords = c(),
                              tokenizeRegex = "([! )(\uc2\uab,.:?\u201e\u201c\'\"]+|&quot;)",
                              oldTable = data.frame(word = rep(NA, 1), frequency = rep(NA, 1)),
                              verbose = TRUE) {
  word <- NULL # https://stackoverflow.com/questions/8096313/no-visible-binding-for-global-variable-note-in-r-cmd-check
  frequency <- NULL

  if (length(snippet) < 1) {
    dplyr::tibble(word=c(), frequency=c())
  } else if (length(snippet) > 1) {
    log.info(verbose, paste("Joinging", length(snippet), "kwics\n"))
    for (s in snippet) {
      oldTable <- snippet2FreqTable(
        s,
        leftContextSize = leftContextSize,
        rightContextSize = rightContextSize,
        oldTable = oldTable,
        stopwords = stopwords
      )
    }
    log.info(verbose, paste("Aggregating", length(oldTable$word), "tokens\n"))
    oldTable  %>%
      group_by(word) %>%
      mutate(word = dplyr::case_when(ignoreCollocateCase ~ tolower(word), TRUE ~ word)) %>%
      summarise(frequency=sum(frequency), .groups = "drop") %>%
      arrange(desc(frequency))
  } else {
    stopwordsTable <- dplyr::tibble(word=stopwords)
    match <-
      str_match(
        snippet,
        '<span class="context-left">(<span class="more"></span>)?(.*[^ ]) *</span><span class="match"><mark>.*</mark></span><span class="context-right"> *([^<]*)'
      )

    left <- if(leftContextSize > 0)
      tail(unlist(str_split(match[1, 3], tokenizeRegex)), leftContextSize)
    else
      ""
#    cat(paste("left:", left, "\n", collapse=" "))

    right <- if(rightContextSize > 0)
      head(unlist(str_split(match[1, 4], tokenizeRegex)), rightContextSize)
    else
        ""
#    cat(paste("right:", right, "\n", collapse=" "))

    if(is.na(left) || is.na(right) || length(left) + length(right) == 0) {
      oldTable
    } else {
      table(c(left, right)) %>%
        dplyr::as_tibble(.name_repair = "minimal") %>%
        dplyr::rename(word = 1, frequency = 2) %>%
        dplyr::filter(str_detect(word, '^[:alnum:]+-?[:alnum:]*$')) %>%
        dplyr::anti_join(stopwordsTable, by="word")  %>%
        dplyr::bind_rows(oldTable)
    }
  }
}

#' Preliminary synsemantic stopwords function
#'
#' @description
#' `r lifecycle::badge("experimental")`
#'
#' Preliminary synsemantic stopwords function to be used in collocation analysis.
#'
#' @details
#' Currently only suitable for German. See stopwords package for other languages.
#'
#' @param ... future arguments for language detection
#'
#' @family collocation analysis functions
#' @return Vector of synsemantic stopwords.
#' @export
synsemanticStopwords <- function(...) {
  res <- c(
    "der",
    "die",
    "und",
    "in",
    "den",
    "von",
    "mit",
    "das",
    "zu",
    "im",
    "ist",
    "auf",
    "sich",
    "Die",
    "des",
    "dem",
    "nicht",
    "ein",
    "eine",
    "es",
    "auch",
    "an",
    "als",
    "am",
    "aus",
    "Der",
    "bei",
    "er",
    "dass",
    "sie",
    "nach",
    "um",
    "Das",
    "zum",
    "noch",
    "war",
    "einen",
    "einer",
    "wie",
    "einem",
    "vor",
    "bis",
    "\u00fcber",
    "so",
    "aber",
    "Eine",
    "diese",
    "Diese",
    "oder"
  )
  return(res)
}

collocatesQuery <-
  function(kco,
           query,
           vc = "",
           minOccur = 5,
           leftContextSize = 5,
           rightContextSize = 5,
           searchHitsSampleLimit = 20000,
           ignoreCollocateCase = FALSE,
           stopwords = c(),
           ...) {
    frequency <- NULL
    q <- corpusQuery(kco, query, vc, metadataOnly = F, ...)
    if(q@totalResults == 0) {
      tibble(word=c(), frequency=c())
    } else {
      q <- fetchNext(q, maxFetch=searchHitsSampleLimit, randomizePageOrder=TRUE)
      snippet2FreqTable((q@collectedMatches)$snippet,
                        minOccur = minOccur,
                        leftContextSize = leftContextSize,
                        rightContextSize = rightContextSize,
                        ignoreCollocateCase = ignoreCollocateCase,
                        stopwords = stopwords,
                        verbose = kco@verbose) %>%
        mutate(frequency = frequency * q@totalResults / min(q@totalResults, searchHitsSampleLimit)) %>%
        filter(frequency >= minOccur)
    }
  }