import Foundation

/// Skip logic
class BWSkipStepNavigationRule: ORKSkipStepNavigationRule {
    let DOUBLE = "double"
    let INT = "int"
    var displayIf: [String: AnyObject] = [:] // it gets reassigned
    var questionTypes: [String: SurveyQuestionType] = [:]
    
    // convenience init with the nscoder populated - I don't know what its for but it was here before me.
    required init(coder: NSCoder) {
        super.init(coder: coder)
    }
    
    // convenience init with displayIf populated
    convenience init(displayIf: [String: AnyObject]?, questionTypes: [String: SurveyQuestionType]) {
        self.init(coder: NSCoder())
        self.displayIf = displayIf ?? [:]
        self.questionTypes = questionTypes // oh woops we aren't even using this anymore...
    }
    
    override func stepShouldSkip(with taskResult: ORKTaskResult) -> Bool {
        // print("stepShouldSkip time!")
        // if there is no skip logic then the question should not be skipped
        
        if self.displayIf.isEmpty {
            // print("\nQUESTION WITHOUT SKIP LOGIC\n")
            return false
        }
        
        if self.displayIf.count != 1 {
            fatalError("Encountered invalid size of outermost displayIf dictionary: \(self.displayIf.count)")
        }
        
        // evaluate - the logic returns true if there is a match, which means we need to invert the output of the logic, lol...
        return !self.evaluateSingleLogicPair(self.displayIf.keys.first!, self.displayIf.values.first!, taskResult)
    }
    
    /// consumes
    func evaluateSingleLogicPair(_ operation: String, _ payload: AnyObject, _ taskResult: ORKTaskResult) -> Bool {
        // print("evaluateSingleLogicPair start")
        // print("operation: \(operation)")
        // print("type of payload: \(payload.classForCoder)")
        // defer {
        //     print("evaluateSingleLogicPair end")
        // }
        
        if ["not", "or", "and"].contains(operation) {
            // for these operators the payload will be a list of other logic pairs, assert that the class is as expected
            guard let payload_dict = payload as? [String: AnyObject] else {
                fatalError("Encountered invalid type of payload dict: \(payload.classForCoder)")
            }
            
            // assert that these values are not nil
            if payload_dict.keys.first == nil || payload_dict.values.first == nil {
                fatalError("Encountered invalid contents of a payload dict: \(payload.classForCoder), key 1:\(payload_dict.keys.first), value 1:\(payload_dict.values.first)")
            }
            
            if operation == "not" {
                // paylaod is a list of length 1
                if payload_dict.count != 1 {
                    fatalError("Encountered invalid size of payload_dict for inversion: \(payload_dict.count)")
                }
                return !self.evaluateSingleLogicPair(payload_dict.keys.first!, payload_dict.values.first!, taskResult)
            }
            
            // 'and' and 'or' should work fine on any size payload_dict
            if operation == "or" {
                for (key, value) in payload_dict {
                    if self.evaluateSingleLogicPair(key, value, taskResult) {
                        return true
                    }
                }
            }
            if operation == "and" {
                for (key, value) in payload_dict {
                    if !self.evaluateSingleLogicPair(key, value, taskResult) {
                        return false
                    }
                }
                return true
            }
        }
        
        // numerical oporation dispatch with USEFUL ERROR MESSAGES.
        if ["==", "<", "<=", ">", ">="].contains(operation) {
            // payload in this case is a list of  two elements, a string (question id) and a numeric value
            guard let payload_list = payload as? [AnyObject] else {
                fatalError("Encountered invalid type for payload list: \(payload.classForCoder)")
            }
            guard payload_list.count == 2 else {
                fatalError("Encountered invalid size of payload list: \(payload_list.count), \(payload_list)")
            }
            guard let target = payload_list[0] as? String else {
                fatalError("Encountered invalid type for questiion id target: \(payload_list[0].classForCoder)")
            }
            guard let compare_me = payload_list[1] as? NSNumber else {
                fatalError("Encountered invalid type for comparison value: \(payload_list[1].classForCoder)")
            }
            return self.numeric_logic(operation, target, compare_me, taskResult)
        }
        
        // should be unreachable
        fatalError("Encountered invalid operation: \(operation)")
    }
    
    /// extracts the answer value to a given question result, indicates via a string the type of logical evaluation required.
    func extractAnswer(_ stepResult: ORKStepResult) -> ([NSNumber], String) {
        // there were no answers to the question, numerical type is irrelevant
        guard let results = stepResult.results, results.count == 0 else {
            return ([NSNumber](), self.DOUBLE)
        }
        
        // I think results[0] is sufficient because we only ever have single answers to questions.
        switch results[0] {
        case let choiceResult as ORKChoiceQuestionResult:
            // choice (radio button and checkbox) questions
            return self.do_choice_stuff(choiceResult)
            
        case let questionResult as ORKQuestionResult:
            // numerical open response questions can provide floating-point answers, so need doubles
            if let answer = questionResult.answer {
                // this magically converts only valid numerical strings - apparently
                if let number = Double(String(describing: answer)) {
                    return ([number as NSNumber], self.DOUBLE)
                }
                return ([NSNumber](), self.DOUBLE)
            }
            
        case let scaleResult as ORKScaleQuestionResult:
            // slider questions use ints
            if let answer: NSNumber = scaleResult.scaleAnswer {
                return ([answer], self.INT)
            }
            return ([NSNumber](), self.INT)
            
        default:
            fatalError("invalid step result type: \(results[0].classForCoder)")
        }
        // um, unreachable
        fatalError("unreachable code in extractAnswer")
    }
    
    /// choice question logic (radio buttons and checkboxes) operates on the selected answer number, rather
    /// than the value of the answer itself. They are slightly more cumbersome so have their own function.
    /// Choice question answers should be interpreted as ints.
    func do_choice_stuff(_ choiceResult: ORKChoiceQuestionResult) -> ([NSNumber], String) {
        guard let choiceAnswers = choiceResult.choiceAnswers else {
            return ([NSNumber](), self.INT)
        }
        
        var selected_answers = [NSNumber]()
        for choiceAnswer in choiceAnswers {
            if let num: NSNumber = choiceAnswer as? NSNumber {
                selected_answers.append(num)
            }
        }
        return (selected_answers, self.INT)
    }
    
    /// takes a numerical operation, a target question, and a comparitor (and the blob of data to extract the question's answer from),
    /// extracts everything correctly, dispatches the correct comparitor.
    func numeric_logic(_ operation: String, _ target: String, _ compare_me: NSNumber, _ taskResult: ORKTaskResult) -> Bool {
        let answer_numbers: [NSNumber]
        let comparison_primitive_type: String
        // if it isn't any of the operators try it as the question id
        if let targetAnswer: ORKStepResult = taskResult.stepResult(forStepIdentifier: target) {
            (answer_numbers, comparison_primitive_type) = self.extractAnswer(targetAnswer)
        } else {
            return true // um, it wasn't anything and we default to should display?
        }
        
        if comparison_primitive_type == self.DOUBLE {
            return self.double_comparisons(operation, compare_me.doubleValue, answer_numbers)
        } else if comparison_primitive_type == self.INT {
            return self.int_comparisons(operation, compare_me.intValue, answer_numbers)
        } else {
            fatalError("Encountered invalid comparison_primitive_type: \(comparison_primitive_type)")
        }
    }
    
    /// some of our data types need to be compared as doubles, others as integers. These functions do the correct operator comparisons.
    /// All our answer outputs are contained as (potentially empty) lists of NSNumbers, so conversion is fairly easy.
    /// Comparisons return true if there are Any matches - this is to allow Checkbox questions to have comprehensible behavior with
    ///   multiselections, and has no effect on other question types.
    func double_comparisons(_ operation: String, _ compare_me: Double, _ numbers: [NSNumber]) -> Bool {
        var answer_numbers = [Double]()
        for num in numbers {
            answer_numbers.append(num.doubleValue)
        }
        
        if operation == "==" {
            for num in answer_numbers { if compare_me == num { return true } }
        } else if operation == "<" {
            for num in answer_numbers { if compare_me < num { return true } }
        } else if operation == "<=" {
            for num in answer_numbers { if compare_me <= num { return true } }
        } else if operation == ">" {
            for num in answer_numbers { if compare_me > num { return true } }
        } else if operation == ">=" {
            for num in answer_numbers { if compare_me >= num { return true } }
        }
        return false
    }
    
    /// see double_comparisons
    func int_comparisons(_ operation: String, _ compare_me: Int, _ numbers: [NSNumber]) -> Bool {
        var answer_numbers = [Int]()
        for num in numbers {
            answer_numbers.append(num.intValue)
        }
        
        if operation == "==" {
            for num in answer_numbers { if compare_me == num { return true } }
        } else if operation == "<" {
            for num in answer_numbers { if compare_me < num { return true } }
        } else if operation == "<=" {
            for num in answer_numbers { if compare_me <= num { return true } }
        } else if operation == ">" {
            for num in answer_numbers { if compare_me > num { return true } }
        } else if operation == ">=" {
            for num in answer_numbers { if compare_me >= num { return true } }
        }
        return false
    }
}
