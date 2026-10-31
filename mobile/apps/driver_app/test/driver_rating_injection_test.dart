import 'package:asm_api_client/asm_api_client.dart';
import 'package:driver_app/main.dart';
import 'package:driver_app/network/driver_rating_gateway.dart';
import 'package:flutter_test/flutter_test.dart';

// B8 pre-check (31 Oct): buildDriverRoot accepted driverRatingGateway and
// dropped it, and DriverApp had no way to take one; the app always built
// its own.
void main() {
  test('buildDriverRoot passes the rating gateway on to DriverApp', () {
    final gateway = ApiDriverRatingGateway(apiGateway: _NoRatingApi());

    final root = buildDriverRoot(driverRatingGateway: gateway);

    expect(root, isA<DriverApp>());
    expect((root as DriverApp).driverRatingGateway, same(gateway));
  });

  testWidgets('DriverApp gives the shell the rating gateway it was given', (
    tester,
  ) async {
    final gateway = ApiDriverRatingGateway(apiGateway: _NoRatingApi());

    await tester.pumpWidget(DriverApp(driverRatingGateway: gateway));
    await tester.pump();

    final shell = tester.widget<DriverShell>(find.byType(DriverShell));
    expect(shell.driverRatingGateway, same(gateway));
  });
}

final class _NoRatingApi implements DriverRatingApiGateway {
  @override
  Future<ApiResponse<T>> get<T>(String path, {JsonDecoder<T>? decoder}) =>
      throw StateError('not used');

  @override
  Future<ApiResponse<T>> post<T>(
    String path, {
    Object? data,
    JsonDecoder<T>? decoder,
  }) => throw StateError('not used');
}
