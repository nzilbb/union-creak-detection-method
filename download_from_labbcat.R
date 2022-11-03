### This script downloads selected wav files and TextGrids from a LaBB-CAT corpus, and
### also creates a corresponding durations.txt file so you don't have to run
### get_durations.praat 
###
### You can run it from the command line using:
### `R --vanilla --slave < download_from_labbcat.R`
###
### Author: robert.fromont@canterbury.ac.nz
### Date: 2022-10-26
###
### Change these setting to suit you own situation:
### LaBB-CAT URL
url <- "http://localhost:8080/labbcat"
### Credentials for logging in to LaBB-CAT
username <- "labbcat"
password <- "labbcat" ## !!! DON'T COMMIT THE REAL PASSWORD TO GIT !!!
### An expression to identify which participants to process, e.g.
### - Participants in a specific corpus: "labels('corpus').includes('QB')"
### - Participant with a given gender: "first('participant_gender').label == 'NB'"
### - Both: "labels('corpus').includes('QB') && first('participant_gender').label == 'NB'"
which.participants <- "/AP.*/.test(id)"
### The directory to download the files to
dir <- "data"

library(nzilbb.labbcat)

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
for (participant.id in participant.ids) {
    transcript.ids <- getTranscriptIdsWithParticipant(url, participant.id)
    for (transcript.id in transcript.ids) {
        ## get wav
        wav.file <- getMedia(url, transcript.id, "", "audio/wav", dir)
        
        if (!is.null(wav.file)) { # there is an audio file
            cat(paste("\n", wav.file, "..."))
            wav.files[[length(wav.files)+1]] <- wav.file
            ## get TextGrid
            textgrid.file <- formatTranscript(
                url, transcript.id, c("segment"), "text/praat-textgrid", dir)
            textgrid.files[[length(textgrid.files)+1]] <- textgrid.file
            
            ## get .pm file
            pm.file <- getMedia(url, transcript.id, "", "application/pm", dir)
            if (!is.null(pm.file)) { ## there is a .pm file
                ## LaBB-CAT will have the native Reaper format, which includes a header that
                ## doesn't match the header created by MacREAPER
                ## Replace the header, and also rename the file the way the other scripts like it
                ## i.e. name.pm -> name.wav.pm
                
                final.pm.file <- paste(wav.file, ".pm", sep="")
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
