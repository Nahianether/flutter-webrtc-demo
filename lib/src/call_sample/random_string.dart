// Copyright (c) 2016, Damon Douglas. All rights reserved. Use of this source code
// is governed by a BSD-style license that can be found in the LICENSE file.

/// Simple library for generating random ascii strings.
///
/// More dartdocs go here.
///
///
/// A simple usage example:
///
/// import 'package:random_string/random_string.dart' as random;
/// main() {
///     debugPrint(randomBetween(10,20)); // some integer between 10 and 20
///     debugPrint(randomNumeric(4)); // sequence of 4 random numbers i.e. 3259
///     debugPrint(randomString(10)); // random sequence of 10 characters i.e. e~f93(4l-
///     debugPrint(randomAlpha(5)); // random sequence of 5 alpha characters i.e. aRztC
///     debugPrint(randomAlphaNumeric(10)); // random sequence of 10 alpha numeric i.e. aRztC1y32B
/// }

library random_string;

import 'dart:math';

const ascciSTART = 33;
const ascciEND = 126;
const numericStart = 48;
const numericEnd = 57;
const lowerAlphaStart = 97;
const lowerAlphaEnd = 122;
const upperAlphaStart = 65;
const upperAlphaEnd = 90;

/// Generates a random integer where [from] <= [to].
int randomBetween(int from, int to) {
  if (from > to) throw Exception('$from cannot be > $to');
  var rand = Random();
  return ((to - from) * rand.nextDouble()).toInt() + from;
}

/// Generates a random string of [length] with characters
/// between ascii [from] to [to].
/// Defaults to characters of ascii '!' to '~'.
String randomString(int length, {int from = ascciSTART, int to = ascciEND}) {
  return String.fromCharCodes(List.generate(length, (index) => randomBetween(from, to)));
}

/// Generates a random string of [length] with only numeric characters.
String randomNumeric(int length) => randomString(length, from: numericStart, to: numericEnd);
/*
/// Generates a random string of [length] with only alpha characters.
String randomAlpha(int length) {
  var lowerAlphaLength = randomBetween(0, length);
  var upperAlphaLength = length - lowerAlphaLength;
  var lowerAlpha = randomString(lowerAlphaLength,
      from: LOWER_ALPHA_START, to: LOWER_ALPHA_END);
  var upperAlpha = randomString(upperAlphaLength,
      from: UPPER_ALPHA_START, to: UPPER_ALPHA_END);
  return randomMerge(lowerAlpha, upperAlpha);
}

/// Generates a random string of [length] with alpha-numeric characters.
String randomAlphaNumeric(int length) {
  var alphaLength = randomBetween(0, length);
  var numericLength = length - alphaLength;
  var alpha = randomAlpha(alphaLength);
  var numeric = randomNumeric(numericLength);
  return randomMerge(alpha, numeric);
}

/// Merge [a] with [b] and scramble characters.
String randomMerge(String a, String b) {
  var mergedCodeUnits = List.from("$a$b".codeUnits);
  mergedCodeUnits.shuffle();
  return String.fromCharCodes(mergedCodeUnits);
}*/
