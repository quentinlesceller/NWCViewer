CXX ?= c++
CXXFLAGS ?= -O2 -std=c++11 -Wall
score-reader: main.cpp LegacyScore.cpp ScoreReader.cpp ScoreReader.h ScoreData.h
	$(CXX) $(CXXFLAGS) main.cpp LegacyScore.cpp ScoreReader.cpp -lz -o $@
