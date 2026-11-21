extends RefCounted
## 测试基类：提供断言，失败信息收集到 failures。

var failures: Array[String] = []
var current: String = ""


func check(cond: bool, msg: String = "") -> bool:
	if not cond:
		failures.append("%s: %s" % [current, msg])
	return cond


func check_eq(actual, expected, msg: String = "") -> bool:
	if actual != expected:
		failures.append("%s: expected <%s> got <%s> %s" % [current, str(expected), str(actual), msg])
		return false
	return true
