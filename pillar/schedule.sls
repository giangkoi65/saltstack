schedule:
  thuc_thi_chong_drift_nginx:
    function: state.apply
    minutes: 15
    args:
      - nginx
    kwargs:
      saltenv: main
      pillarenv: main
      test: True
