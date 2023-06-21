import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';

Future<Map<dynamic, dynamic>> getTurnCredential(String host, int port) async {
  HttpClient client = HttpClient(context: SecurityContext());
  client.badCertificateCallback = (X509Certificate cert, String host, int port) {
    debugPrint('getTurnCredential: Allow self-signed certificate => $host:$port. ');
    return true;
  };
  var url = 'https://$host:$port/api/turn?service=turn&username=flutter-webrtc';
  var request = await client.getUrl(Uri.parse(url));
  var response = await request.close();
  var responseBody = await response.transform(const Utf8Decoder()).join();
  debugPrint('getTurnCredential:response => $responseBody.');
  return const JsonDecoder().convert(responseBody);
}
