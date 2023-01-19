### This script downloads selected wav files and TextGrids from a LaBB-CAT corpus, and
### also creates a corresponding durations.txt file so you don't have to run
### get_durations.praat
###
### Make sure you change the settings below to suit your situation before execution.
###
### Packages that must be installed:
###  - nzilbb.labbcat
###  - rPraat
###
### You can run it from the command line using:
### `R --vanilla --slave < download_from_labbcat.R`
###
### What to do after getting data from LaBB-CAT:
### 1. Run create_phoneme_files.R
### 1.1 Edit setwd path to match dir below
### 1.2 Run create_phoneme_files.R
### 2. Run create_pm_files.R
### 2.1 Edit setwd path to match dir below
### 2.2 Set chunked.files = FALSE
### 2.3 Run create_pm_files.R
### 3. Run get_am_output_sonorants.R
### 3.1 Edit setwd path to match dir below
### 3.2 The script assumes the SAMPA phoneme labels that are produced by WebMAUS.
###     If LaBB-CAT uses a different phoneme set (it probably does!) then change the filter
###     after line 38 to match your sonorant symbols.
###     e.g. CELEX DISC sonorants are:
###          c C E F H i I P q Q u U V 0 1 2 3 4 5 6 7 8 9 ~ # { $ @
###          j l m n N r w 
###
### Author: robert.fromont@canterbury.ac.nz
### Date: 2022-10-26
###

####### Change these setting to suit you own situation: #######

### LaBB-CAT URL
url <- "http://localhost:8080/labbcat/"

### Credentials for logging in to LaBB-CAT
username <- "labbcat"
password <- "labbcat" ## !!! DON'T COMMIT THE REAL PASSWORD TO GIT !!!

### An expression to identify which participants to process, e.g.
### - Participants in a specific corpus: "labels('corpus').includes('QB')"
### - Participant with a given gender: "first('participant_gender').label == 'NB'"
### - Both: "labels('corpus').includes('QB') && first('participant_gender').label == 'NB'"
which.participants <- "/^AP51[13].*/.test(id)"
## (^AP51[12].* identifies just a couple of participants for testing purposes)

### The directory to download the files to
### NB: this script deletes everything in here before doing anything else
dir <- "data"

################## End of settings to update ##################

devtools::install_github("nzilbb/labbcat-R", "1.2-0")
library(nzilbb.labbcat)
library(rPraat)

## Downloading wav files can be time consuming, so up the timeout to 5 minutes
labbcatTimeout(300)

## get username/password
error <- labbcatCredentials(url, username, password)
if (!is.null(error)) {
    print(error)
    exit()
}

cat("\nGetting participant IDs:", which.participants, "...")
participant.ids <- getMatchingParticipantIds(url, which.participants)

cat("\nGetting all transcripts for", length(participant.ids), "participants...")
wav.files <- list()
textgrid.files <- list()
pm.files <- list()

unlink(dir, recursive=TRUE)

# create durations.txt on the fly so we don't have to run get_durations.praat
durations.file <- file.path(dir, "durations.txt")
if (file.exists(durations.file)) {
    file.remove(durations.file)
}

# for each participant
for (participant.id in participant.ids) {
    cat("\n", participant.id, "...", sep = "")
    transcript.ids <- getTranscriptIdsWithParticipant(url, participant.id)
    for (transcript.id in transcript.ids) {
        cat("\n ", transcript.id, "...", sep = "")
        ## get wav
        wav.file <- getMedia(url, transcript.id, "", "audio/wav", dir)
        
        if (!is.null(wav.file)) { # there is an audio file
            ## rename wav the way other scripts like it
            final.wav.file <- file.path(
                ## add 'file' number so create_pm_files.R works
                dir, sub(".wav", "_1.wav",
                         ## convert _ -> -
                         gsub("_", "-", basename(wav.file)))) 
            file.rename(from=wav.file, to=final.wav.file)

            cat("\n", wav.file, " (", final.wav.file, ")...", sep = "")
            wav.files[[length(wav.files)+1]] <- final.wav.file
            ## get TextGrid
            textgrid.file <- formatTranscript(
                url, transcript.id, c("segment"), "text/praat-textgrid", dir)
            ## Rename the TextGrid the way the other scripts like it
            ## i.e. some_name.TextGrid -> some-name_pipeline.TextGrid
            final.textgrid.file <- file.path(
                ## ${name}_1_pipeline.TextGrid so that create_phoneme_files.R works
                dir, sub(".TextGrid", "_1_pipeline.TextGrid",
                         ## convert _ -> -
                         gsub("_", "-", basename(textgrid.file)))) 
            file.rename(from=textgrid.file, to=final.textgrid.file)
            textgrid.files[[length(textgrid.files)+1]] <- final.textgrid.file

            ## infer duration from TextGrid
            textgrid <- tg.read(final.textgrid.file)
            duration <- tg.getEndTime(textgrid)
            write(paste(basename(final.wav.file), duration, sep="\t"),
                  file=durations.file, append=TRUE)
            
            ## get .pm file
            pm.file <- getMedia(url, transcript.id, "", "application/pm", dir)
            if (!is.null(pm.file)) { ## there is a .pm file
                ## LaBB-CAT will have the native Reaper format, which includes a header that
                ## doesn't match the header created by MacREAPER
                ## Replace the header, and also rename the file the way the other scripts like it
                ## i.e. name.pm -> name.wav.pm
                
                final.pm.file <- paste(final.wav.file, ".pm", sep="")
                est.header <- TRUE
                pm <- file(description = pm.file, open="r", blocking = TRUE)
                repeat {
                    line <- readLines(pm, n = 1) # Read one line from the connection.
                    if (identical(line, character(0))) break # the end of the file
                    if (est.header) { # still in the EST header
                        if (line == "EST_Header_End") { # got to the end of the header
                            est.header <- FALSE
                            ## write the MacREAPER header
                            write("time voicing f0", file=final.pm.file, append=TRUE)
                        }
                    } else { # past the header, just copy through the line
                        write(line, file=final.pm.file, append=TRUE)
                    }
                } # next line
                close(pm)
                rm(pm)
                file.remove(pm.file)
                pm.files[[length(pm.files)+1]] <- final.pm.file
            } # there is a .pm file
        } # there is an audio file
    } # next transcript
} # next participant

cat("\nFinished.", length(wav.files)+length(textgrid.files)+length(pm.files), "data files are in:", dir, "\n")
