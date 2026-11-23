import 'link.dart';

const bool localLinkSupported = false;

HostLink createLocalHostLink() => throw UnsupportedError('Local links are web-only');
ClientLink createLocalClientLink() => throw UnsupportedError('Local links are web-only');
