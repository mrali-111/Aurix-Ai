import 'dart:convert';
import 'package:http/http.dart' as http;
import '../utils/constants.dart';

class PaymentService {
  Future<void> payWithJazzCash() async {
    try {
      var body = {
        "pp_MerchantID": JAZZCASH_MERCHANT_ID, // 🔴 ADD FROM CONSTANTS
        "pp_Password": JAZZCASH_PASSWORD, // 🔴 ADD
        "pp_Amount": "20000", // 🔴 200 RS = 20000 paisa
        "pp_ReturnURL": JAZZCASH_RETURN_URL // 🔴 ADD
      };

      var response = await http.post(
        Uri.parse("https://sandbox.jazzcash.com.pk/ApplicationAPI/API/Payment/DoTransaction"),
        body: body,
      );

      print("JazzCash Response: ${response.body}");
    } catch (e) {
      print("Payment Error: $e");
    }
  }
}