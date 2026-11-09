import Foundation
struct Case { let name: String; let app: String; let title: String; let body: String; let expect: RuleResult.Decision }
let zw = "\u{200B}"
let cases: [Case] = [
  Case(name: "Korean fine SMS", app: "Messages", title: "+82 10-5521-0937", body: "[국외발신] 도로 관리24: 미납 과태료 안내. 오늘까지 납부하지 않으면 가산금이 부과됩니다. https://sw.example/RJMkq", expect: .analyze),
  Case(name: "Teacher WhatsApp", app: "WhatsApp", title: "Cikgu Rahman", body: "Salam, please review the attached statement of account. Open it on a computer, it's not visible on mobile. Forward to your finance manager.", expect: .analyze),
  Case(name: "Parcel fee", app: "Messages", title: "+82 2-123-4567", body: "Your parcel is held at customs. Pay the ₩3,000 redelivery fee within 24 hours: https://bit.ly/example", expect: .analyze),
  Case(name: "Lost phone RM2000", app: "WhatsApp", title: "+60 11-2345 6789", body: "Mum it's me, I lost my phone. Can you transfer RM2000?", expect: .analyze),
  Case(name: "Investment", app: "WhatsApp", title: "Ken", body: "Join our investment group, guaranteed returns 20% monthly", expect: .analyze),
  Case(name: "Korean new phone", app: "Messages", title: "+82 10-1111-2222", body: "엄마 나 폰 액정 깨져서 임시폰이야. 급하게 송금 좀 해줄 수 있어?", expect: .analyze),
  Case(name: "Dinner", app: "WhatsApp", title: "Daniel", body: "Dinner at 7 tonight?", expect: .skip),
  Case(name: "Clinic", app: "Messages", title: "Klinik Sejahtera", body: "Reminder: your appointment is tomorrow at 10am.", expect: .skip),
  Case(name: "Real DHL", app: "Messages", title: "DHL", body: "Your DHL parcel will be delivered today between 2-5pm.", expect: .skip),
  Case(name: "Bank OTP", app: "Messages", title: "Maybank", body: "Your OTP is 482913. Do not share it with anyone.", expect: .skip),
  Case(name: "KB code", app: "Messages", title: "KB Bank", body: "[KB] 인증번호 482913. 타인에게 절대 알려주지 마세요.", expect: .skip),
  Case(name: "Photo", app: "WhatsApp", title: "Sara", body: "📷 Photo", expect: .skip),
  Case(name: "hi", app: "WhatsApp", title: "Sara", body: "hi", expect: .skip),
  Case(name: "salam hutang (with marks)", app: "WhatsApp", title: "\u{200E}Ali\u{200F}", body: "\u{200E}salam boleh bayar hutang tak", expect: .skip),
  Case(name: "I'm fine", app: "WhatsApp", title: "Sara", body: "I'm fine thanks, see you", expect: .skip),
  Case(name: "Hidden chars inside words + link", app: "Messages", title: "Info", body: "Ve\(zw)rify your acc\(zw)ount at http://x.example/a", expect: .analyze),
  Case(name: "3 new messages", app: "WhatsApp", title: "WhatsApp", body: "3 new messages", expect: .ignored),
  Case(name: "Empty", app: "WhatsApp", title: "Sara", body: "   ", expect: .ignored),
  Case(name: "Failed to send", app: "Messages", title: "Message Failed to Send", body: "The message to Ali failed to send.", expect: .ignored),
]
var fails = 0
for c in cases {
  let r = RulesEngine.evaluate(app: c.app, title: c.title, subtitle: "", body: c.body)
  let ok = r.decision == c.expect
  if !ok { fails += 1 }
  print(ok ? "PASS" : "FAIL", c.name, "→", r.decision, r.score, r.signals.map(\.id), r.isOneTimeCode ? "(code)" : "")
}
print(fails == 0 ? "ALL \(cases.count) PASS" : "\(fails) FAILED")
